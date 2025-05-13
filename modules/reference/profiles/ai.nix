# Copyright 2024 TII (SSRC)
# SPDX-License-Identifier: Apache-2.0

{ config, lib, pkgs, ... }:
let
  cfg = config.ghaf.reference.profiles.ai-dev;
in
{
  options.ghaf.reference.profiles.ai-dev = {
    enable = lib.mkEnableOption "Enable the AI development profile with LLM tools and minimal services";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      graphics.labwc.autologinUser = lib.mkForce null;

      virtualization.microvm-host.sharedVmDirectory.vms = [
        "dev-vm"
      ];

      virtualization.microvm.appvm = {
        enable = true;
        vms = {
          dev = {
            enable = true;

            # Add Python and AI tools into this VM
            user.packages = with pkgs; [
              git
              python310
              python310Packages.pip
              python310Packages.virtualenv
              python310Packages.setuptools
              python310Packages.wheel
              python310Packages.torch
              python310Packages.transformers
            ];
          };
        };
      };

      reference = {
        appvms.enable = true;

        personalize.keys.enable = true;

        desktop.applications.enable = true;

        services = {
          enable = false;
          dendrite = false;
          google-chromecast = false;
          wireguard-gui = false;
          alpaca-ollama = false;
        };
      };

      profiles = {
        laptop-x86 = {
          enable = true;
          netvmExtraModules = [
            ../personalize
            { ghaf.reference.personalize.keys.enable = true; }
          ];
          guivmExtraModules = [
            ../programs
            ../personalize
            { ghaf.reference.personalize.keys.enable = true; }
          ];
        };
      };

      logging = {
        enable = true;
        server.endpoint = "https://loki.ghaflogs.vedenemo.dev/loki/api/v1/push";
        listener.address = config.ghaf.networking.hosts.admin-vm.ipv4;
      };
    };
  };
}
