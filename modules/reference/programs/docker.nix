# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.programs.docker;

in
{
  options.ghaf.reference.programs.docker = {
    enable = lib.mkEnableOption "docker program settings";
  };
  config = lib.mkIf cfg.enable {

    # Terminal
    fonts.packages = [ pkgs.nerd-fonts.fira-code ];
    programs.foot = {
      enable = true;
      settings.main.font = "FiraCode Nerd Font Mono:size=10";
    };

  };
}
