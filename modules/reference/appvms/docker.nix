# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  lib,
  config,
  ...
}:
{
  docker = {
    packages = [
      pkgs.docker
      pkgs.docker-client
      pkgs.docker-compose
      pkgs.docker-credential-helpers
      pkgs.kubernetes
    ] ++ lib.optionals config.ghaf.profiles.debug.enable [ pkgs.tcpdump ];
    ramMb = 4096;
    cores = 4;
    borderColor = "#000000";
    applications = [
      {
        name = "Docker cli";
        description = "Docker";
        icon = "docker-desktop";
        command = "foot";
      }
    ];

    extraModules = [
      {
        imports = [ ../programs/docker.nix ];

        ghaf.reference.programs.docker.enable = true;
      }
    ];
  };
}
