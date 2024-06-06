# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{pkgs, ...}: let
  xdgPdfPort = 1200;
in {
  name = "trusted";
  packages = let
    # PDF XDG handler is executed when the user opens a PDF file in the browser
    # The xdgopenpdf script sends a command to the guivm with the file path over TCP connection
    xdgPdfItem = pkgs.makeDesktopItem {
      name = "ghaf-pdf";
      desktopName = "Ghaf PDF handler";
      exec = "${xdgOpenPdf}/bin/xdgopenpdf %u";
      mimeTypes = ["application/pdf"];
    };
    xdgOpenPdf = pkgs.writeShellScriptBin "xdgopenpdf" ''
      filepath=$(realpath "$1")
      echo "Opening $filepath" | systemd-cat -p info
      echo $filepath | ${pkgs.netcat}/bin/nc -N gui-vm.ghaf ${toString xdgPdfPort}
    '';
  in [
    pkgs.chromium
    pkgs.xdg-utils
    xdgPdfItem
    xdgOpenPdf
  ];
  # TODO create a repository of mac addresses to avoid conflicts
  macAddress = "02:00:00:03:10:01";
  ramMb = 3072;
  cores = 4;
  extraModules = [
    {
      time.timeZone = "Asia/Dubai";

      # Disable chromium built-in PDF viewer to make it execute xdg-open
      programs.chromium.enable = true;
      programs.chromium.extraOpts."AlwaysOpenPdfExternally" = true;
      # Set default PDF XDG handler
      xdg.mime.defaultApplications."application/pdf" = "ghaf-pdf.desktop";
    }
  ];
  borderColor = "#00FF00";
  vtpm.enable = true;
}
