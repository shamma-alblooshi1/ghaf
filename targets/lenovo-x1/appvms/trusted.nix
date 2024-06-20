# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ pkgs,lib,config, ... }: let
  xdgPdfPort = 1200;
in {
  name = "trusted";
  packages = let
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
    pkgs.nftables
    pkgs.globalprotect-openconnect
    pkgs.openconnect
  ];
  macAddress = "02:00:00:03:10:01";
  ramMb = 3072;
  cores = 4;
  extraModules = [
    {
      time.timeZone = "Asia/Dubai";

      programs.chromium.enable = true;
      programs.chromium.extraOpts."AlwaysOpenPdfExternally" = true;
      xdg.mime.defaultApplications."application/pdf" = "ghaf-pdf.desktop";

     
      networking = {
      firewall.enable = true;
      # firewall.extraCommands = "   
      # iptables -F

      # # Allow Microsoft365 only
      # iptables -I OUTPUT -p tcp -d 13.107.6.156 --dport 80 -j ACCEPT
      # iptables -I OUTPUT -p tcp -d 13.107.6.156 --dport 443 -j ACCEPT
      # iptables -I nixos-fw-accept -p tcp -d 13.107.6.156 --dport 80 -j ACCEPT
      # iptables -I nixos-fw-accept -p tcp -d 13.107.6.156 --dport 443 -j ACCEPT

      # # Block HTTP and HTTPS traffic
      # iptables -A OUTPUT -p tcp --dport 80 -j REJECT
      # iptables -A OUTPUT -p tcp --dport 443 -j REJECT
      # ";
    };

  systemd.services.globalprotect = {
    enable = true;
    #csdWrapper = "${pkgs.openconnect}/libexec/openconnect/hipreport.sh";
  };

  # This also enable the gpclient.
  systemd.services = {
    gpclient = {
      description = "A GlobalProtect VPN client (GUI)";
      wantedBy = [ "multi-user.target" ];
      enable = true;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.globalprotect-openconnect}/bin/gpclient";
        Restart = "on-failure";
        RestartSec = 3;
      };
     
    };
  };

    }
  ];
  borderColor = "#00FF00";
  vtpm.enable = true;
}
