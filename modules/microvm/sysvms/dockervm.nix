# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  ...
}:
let
  configHost = config;
  vmName = "docker-vm";

  dockervmBaseConfiguration = {
    imports = [
      inputs.impermanence.nixosModules.impermanence
      inputs.self.nixosModules.givc
      inputs.self.nixosModules.vm-modules
      inputs.self.nixosModules.profiles
      (
        { lib, pkgs, ... }:
        {
          ghaf = {
            # Profiles
            profiles.debug.enable = lib.mkDefault configHost.ghaf.profiles.debug.enable;
            development = {
              ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
            };
            users.proxyUser = {
              enable = true;
              extraGroups = [
                "docker"
              ];
            };

            # System
            type = "system-vm";
            systemd = {
              enable = true;
              withName = "dockervm-systemd";
              withAudit = configHost.ghaf.profiles.debug.enable;
              withNss = true;
              withResolved = true;
              withTimesyncd = true;
              withDebug = configHost.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };
            givc.dockervm.enable = true;

            # Storage
            storagevm = {
              enable = true;
              name = vmName;
              directories = [ "/var/lib/docker" ];
            };

            # Networking
            virtualization.microvm.vm-networking = {
              enable = true;
              inherit vmName;
            };

            # Services
            logging.client.enable = configHost.ghaf.logging.enable;
          };

          # Enable Docker
          virtualisation = {
            docker = {
              enable = true;
              enableOnBoot = true;
            };
          };

          # Docker Desktop requires these
          boot.kernel.sysctl = {
            "net.ipv4.ip_forward" = 1;
            "net.ipv6.conf.all.forwarding" = 1;
          };

          environment = {
            systemPackages = with pkgs; [
              # Docker CLI and related tools
              docker
              docker-client

              # Docker Desktop packages (to be changed)
              docker-compose
              docker-credential-helpers
              kubernetes

            ];
          };

          time.timeZone = config.time.timeZone;
          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
            hostPlatform.system = configHost.nixpkgs.hostPlatform.system;
          };

          microvm = {
            optimize.enable = false;
            vcpu = 4;
            mem = 4096;
            hypervisor = "qemu";
            shares = [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "virtiofs";
              }
            ];
            writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";
            qemu = {
              machine =
                {
                  # Use the same machine type as the host
                  x86_64-linux = "q35";
                  aarch64-linux = "virt";
                }
                .${configHost.nixpkgs.hostPlatform.system};
              extraArgs = [
                "-device"
                "qemu-xhci"
                "-device"
                "vhost-vsock-pci,guest-cid=${toString config.ghaf.networking.hosts.${vmName}.cid}"
              ];
            };
          };
        }
      )
    ];
  };
  cfg = config.ghaf.virtualization.microvm.dockervm;
in
{
  options.ghaf.virtualization.microvm.dockervm = {
    enable = lib.mkEnableOption "DockerVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of                    
        DockerVM's NixOS configuration.                                                       
      '';
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      inherit (inputs) nixpkgs;
      config = dockervmBaseConfiguration // {
        imports = dockervmBaseConfiguration.imports ++ cfg.extraModules;
      };
    };
  };
}
