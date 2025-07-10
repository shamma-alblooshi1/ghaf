# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  ...
}:
{
  agents = {
    ramMb = 2048;
    cores = 2;
    borderColor = "#4A90E2"; # Blue color for AI/ML theme
    ghafAudio.enable = false;
    vtpm.enable = true; # Enable for security
    applications = [
      {
        name = "Multi-Agent Framework";
        description = "AI Multi-Agent Framework with MCP Tools";
        packages = [
          pkgs.agents
        ];
        icon = "";
        command = "";
        extraModules = [
          {

            environment.systemPackages = [
            ];

            # Optional: Create a service
            systemd.user.services.multiagent-framework = {
              description = "Multi-Agent Framework Service";
              serviceConfig = {
                Type = "simple";
                Restart = "always";
                RestartSec = "10";
              };
              enable = false;
            };
          }
        ];
      }
    ];
    extraModules = [
      {

      }
    ];
  };
}
