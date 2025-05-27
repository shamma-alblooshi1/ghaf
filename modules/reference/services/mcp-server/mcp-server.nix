# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.ghaf.reference.services.mcp-server;
in
{
  options.ghaf.reference.services.mcp-server = {
    enable = mkEnableOption "MCP server for AI agents";

    port = mkOption {
      type = types.port;
      default = 1337;
      description = "Port to listen on";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address to bind to";
    };

    logLevel = mkOption {
      type = types.enum [ "debug" "info" "warning" "error" ];
      default = "info";
      description = "Log level for the MCP server";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/mcp-server";
      description = "Directory to store MCP server state";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall for the MCP server port";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.mcp-server = {
      description = "MCP Server for AI Agents";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      
      serviceConfig = {
        ExecStart = "${pkgs.mcp-server}/bin/mcp-server --host ${cfg.host} --port ${toString cfg.port} --log-level ${cfg.logLevel} --state-dir ${cfg.stateDir}";
        Restart = "on-failure";
        RestartSec = "5s";
        User = "mcp";
        Group = "mcp";
        StateDirectory = "mcp-server";
        StateDirectoryMode = "0750";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
      };
    };

    users.users.mcp = {
      isSystemUser = true;
      group = "mcp";
      description = "MCP server user";
      home = cfg.stateDir;
      createHome = true;
    };

    users.groups.mcp = {};

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
