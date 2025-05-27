# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  ...
}:
{
  jan = {
    ramMb = 4096;
    cores = 4;
    borderColor = "#027d7b";
    applications = [
      {
        name = "Jan Desktop";
        description = "Jan Desktop to run Ai";
        packages = [ pkgs.jan ];
        icon = "Hand";
        command = "jan";
      }
    ];
  };
}
