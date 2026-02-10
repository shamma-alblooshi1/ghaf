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
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.bindPort ];

    # --- Join token generation (PoC) ---
    systemd.tmpfiles.rules = lib.mkIf cfg.generateJoinTokens [
      "d ${cfg.tokenDir} 0750 root root - -"
    ];

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

      # Provide tools in PATH (awk, mkdir, etc.)
      path = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.spire
      ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = pkgs.writeShellScript "spire-generate-join-tokens" ''
          set -euo pipefail
          mkdir -p "${cfg.tokenDir}"
          # Wait until the server is up (best-effort)
          for i in $(seq 1 30); do
            if spire-server healthcheck >/dev/null 2>&1; then
              break
            fi
            sleep 1
          done
          for vm in ${lib.concatStringsSep " " cfg.spireAgentVMs}; do
            f="${cfg.tokenDir}/''${vm}.token"
            if [ -s "$f" ]; then
              echo "token exists: $f"
              continue
            fi
            echo "creating token for $vm"
            token="$(spire-server token generate \
              -spiffeID "spiffe://${cfg.trustDomain}/spire/agent/''${vm}" \
              | awk '/^Token:/ {print $2}')"
            umask 0077
            printf '%s\n' "$token" > "$f"
            chmod 0440 "$f"
            chown root:root "$f"
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
          # Export current bundle from the server
          spire-server bundle show > "$out"
          chmod 0644 "$out"
          chown root:root "$out"
          echo "Wrote $out"
        '';
      };
    };
  };
}
