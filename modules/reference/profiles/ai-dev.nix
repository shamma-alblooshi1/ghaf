# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib,pkgs, ... }:
let
  cfg = config.ghaf.reference.profiles.ai-dev;
in
{
  options.ghaf.reference.profiles.ai-dev = {
    enable = lib.mkEnableOption "Enable the mvp configuration for apps and services";
  };

  config = lib.mkIf cfg.enable {

      environment = {
      systemPackages =
        with pkgs; [
      python311
      python311Packages.pip
      python311Packages.virtualenv
      python311Packages.setuptools
      python311Packages.wheel
      python311Packages.torch
      python311Packages.transformers
    ];
     };
     
    ghaf = {
      # Enable below option for session lock feature
      graphics = {
        #might be too optimistic to hide the boot logs
        #just yet :)
        # boot.enable = lib.mkForce true;
        labwc = {
          autologinUser = lib.mkForce null;
        };
      };
      # Enable shared directories for the selected VMs
      virtualization.microvm-host.sharedVmDirectory.vms = [
        "business-vm"
        "comms-vm"
        "chrome-vm"
      ];


      virtualization.microvm.appvm = {
        enable = true;
        vms = {
          chrome.enable = true;
          gala.enable = false;
          zathura.enable = false;
          comms.enable = false;
          business.enable = false;
        };
      };

      reference = {
        appvms.enable = true;

        services = {
          enable = true;
          dendrite = false;
          proxy-business = lib.mkForce config.ghaf.virtualization.microvm.appvm.vms.business.enable;
          google-chromecast = false;
          alpaca-ollama = true;
          wireguard-gui = true;
        };

        personalize = {
          keys.enable = true;
        };

        desktop.applications.enable = true;
      };

      profiles = {
        laptop-x86 = {
          enable = true;
          netvmExtraModules = [
            ../services
            ../personalize
            { ghaf.reference.personalize.keys.enable = true; }
          ];
          guivmExtraModules = [
            ../services
            ../programs
            ../personalize
            { ghaf.reference.personalize.keys.enable = true; }
          ];
        };
      };

      # Enable logging
      logging = {
        enable = true;
        server.endpoint = "https://loki.ghaflogs.vedenemo.dev/loki/api/v1/push";
        listener.address = config.ghaf.networking.hosts.admin-vm.ipv4;
      };
    };
  };
}
