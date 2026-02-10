# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.spiffe.server;
in
{
  options.ghaf.security.spiffe.server = {
    enable = lib.mkEnableOption "SPIRE server";

    trustDomain = lib.mkOption {
      type = lib.types.str;
      default = "ghaf.internal";
      description = "SPIFFE trust domain served by SPIRE server";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "SPIRE server bind address";
    };

    bindPort = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = "SPIRE server bind port (agents connect here)";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/spire/server";
      description = "SPIRE server state directory";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "INFO";
      description = "SPIRE server log level";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall for SPIRE server bind port";
    };

    spireAgentVMs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of VM names that will run spire-agent (join token will be created if missing).";
    };

    tokenDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common/spire/tokens";
      description = "Directory where join tokens are stored (typically backed by /persist/common via virtiofs).";
    };

    bundleOutPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common/spire/bundle.pem";
      description = "Path where the SPIRE trust bundle is published (typically backed by /persist/common).";
    };

    generateJoinTokens = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the PoC systemd oneshot that generates join tokens for listed VMs.";
    };

    publishBundle = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the PoC systemd oneshot that publishes the SPIRE trust bundle to bundleOutPath.";
    };

    socketpath = lib.mkOption {
      type = lib.types.str;
      default = "/tmp/spire-server/private/api.sock";
      description = "Unix socket for spire-server";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.spire-server ];

    users.groups.spire = { };
    users.users.spire = {
      isSystemUser = true;
      group = "spire";
    };

    environment.etc."spire/server.conf".text = ''
      server {
        bind_address = "${cfg.bindAddress}"
        bind_port = ${toString cfg.bindPort}
        trust_domain = "${cfg.trustDomain}"
        data_dir = "${cfg.dataDir}"
        log_level = "${cfg.logLevel}"
        socket_path="${cfg.socketpath}"
      }
      plugins {
        DataStore "sql" {
          plugin_data {
            database_type = "sqlite3"
            connection_string = "${cfg.dataDir}/datastore.sqlite3"
          }
        }
        KeyManager "disk" {
          plugin_data {
            keys_path = "${cfg.dataDir}/keys.json"
          }
        }
        # PoC/benchmark node attestation:
        NodeAttestor "join_token" {
          plugin_data {}
        }
      }
    '';

    # --- Join token generation (PoC) ---
    systemd.tmpfiles.rules = [
      "d /tmp/spire-server 0755 root root - -"
      "d /tmp/spire-server/private 0755 spire spire - -"
    ]
    ++ lib.optionals cfg.generateJoinTokens [
      "d ${cfg.tokenDir} 0755 root root - -"
    ];

    systemd.services.spire-server = {
      description = "SPIRE Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        User = "spire";
        Group = "spire";

        ExecStart = "${pkgs.spire-server}/bin/spire-server run -config /etc/spire/server.conf";

        StateDirectory = "spire/server";
        StateDirectoryMode = "0750";

        Restart = "on-failure";
        RestartSec = "2s";

        NoNewPrivileges = true;
        PrivateTmp = false;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          cfg.dataDir
          "/tmp/spire-server"
        ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.bindPort ];

    systemd.services.spire-generate-join-tokens = lib.mkIf cfg.generateJoinTokens {
      description = "Generate SPIRE join tokens for Ghaf VMs (PoC)";
      wantedBy = [ "multi-user.target" ];
      after = [
        "spire-server.service"
        "network-online.target"
      ];
      wants = [
        "spire-server.service"
        "network-online.target"
      ];

      path = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.spire-server
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        ExecStart = pkgs.writeShellScript "spire-generate-join-tokens" ''
          set -euo pipefail
          mkdir -p "${cfg.tokenDir}"
          chmod 755 "${cfg.tokenDir}"

          # Wait until the server is up
          for i in $(seq 1 60); do
            if spire-server healthcheck -socketPath ${cfg.socketpath} >/dev/null 2>&1; then
              echo "SPIRE server is ready"
              break
            fi
            echo "Waiting for SPIRE server... ($i/60)"
            sleep 1
          done

          for vm in ${lib.concatStringsSep " " cfg.spireAgentVMs}; do
            f="${cfg.tokenDir}/''${vm}.token"

            # Check if agent is already registered
            if spire-server agent list -socketPath ${cfg.socketpath} 2>/dev/null | grep -q "spiffe://${cfg.trustDomain}/agent/''${vm}"; then
              echo "Agent $vm already registered, skipping token generation"
              continue
            fi

            echo "Generating new token for $vm"
            token="$(spire-server token generate \
              -socketPath ${cfg.socketpath} \
              -spiffeID "spiffe://${cfg.trustDomain}/agent/''${vm}" \
              | awk '/^Token:/ {print $2}')"

            printf '%s\n' "$token" > "$f"
            chmod 0644 "$f"
            echo "Token written to $f"
          done
        '';
      };
    };

    # --- Bundle publishing (PoC) ---
    systemd.services.spire-publish-bundle = lib.mkIf cfg.publishBundle {
      description = "Publish SPIRE trust bundle (PoC)";
      wantedBy = [ "multi-user.target" ];
      after = [ "spire-server.service" ];
      wants = [ "spire-server.service" ];

      path = [
        pkgs.coreutils
        pkgs.spire
      ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = pkgs.writeShellScript "spire-publish-bundle" ''
          set -euo pipefail
          out="${cfg.bundleOutPath}"
          mkdir -p "$(dirname "$out")"
          # Wait until the server API socket exists and the server is ready
          for i in $(seq 1 60); do
            if [ -S "${cfg.socketpath}" ] && spire-server healthcheck -socketPath "${cfg.socketpath}" >/dev/null 2>&1; then
              break
            fi
            sleep 1
          done
          if [ ! -S "${cfg.socketpath}" ]; then
            echo "ERROR: SPIRE server socket not found at ${cfg.socketpath}" >&2
            exit 1
          fi
          tmp="$(mktemp)"
          spire-server bundle show -socketPath "${cfg.socketpath}" > "$tmp"
          if [ ! -s "$tmp" ]; then
            echo "ERROR: bundle export produced empty output" >&2
            exit 1
          fi
          install -m 0644 -o root -g root "$tmp" "$out"
          rm -f "$tmp"
          echo "Wrote $out"
        '';
      };
    };
  };
}
