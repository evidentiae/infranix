{ name, config, pkgs, lib, ... }:

with lib;
with builtins;

let

  cfg = config.libvirt;

  inherit (import ../lib.nix) mkUUID mkMAC;

  sys = config.nixos.out.system;

  libvirtxml = ''
    <domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
      <name>${cfg.name}</name>
      <uuid>${cfg.uuid}</uuid>
      <memory unit='M'>${toString cfg.memory}</memory>
      <currentMemory unit='M'>${toString cfg.memory}</currentMemory>
      <vcpu placement='static'>2</vcpu>
      <os>
        <type>hvm</type>
        <kernel>${sys}/kernel</kernel>
        <initrd>${sys}/initrd</initrd>
        <cmdline>$(cat ${sys}/kernel-params) console=ttyS0 init=${sys}/init</cmdline>
      </os>
      <features><acpi/></features>
      <cpu><model>kvm64</model></cpu>
      <clock offset='utc'/>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>destroy</on_reboot>
      <on_crash>destroy</on_crash>
      <devices>
        <emulator>${pkgs.qemu}/bin/qemu-system-x86_64</emulator>
        <memballoon model='virtio'/>
        <serial type='pty'><target port='0'/></serial>
        <console type='pty'><target type='serial' port='0'/></console>
        ${concatStrings (mapAttrsToList (n: dev: ''
          <interface type='network'>
            <model type='virtio'/>
            <mac address='${dev.mac}'/>
            <source network='${dev.network}'/>
          </interface>
        '') cfg.netdevs)}
        ${concatStrings (mapAttrsToList (n: share: ''
          <filesystem type='mount' accessmode='${share.accessMode}'>
            <source dir='${optionalString (substring 0 1 share.hostPath != "/") "@PWD@"}${share.hostPath}'/>
            <target dir='${n}'/>
            ${optionalString share.readOnly "<readonly/>"}
          </filesystem>
        '') cfg.fileShares)}
      </devices>
    </domain>
  '';

in {
  imports = [
    <imsl-nix-modules/builders/nixos.nix>
  ];

  options = {
    libvirt = {
      xml = mkOption {
        type = types.str;
        default = libvirtxml;
      };
      xmlFile = mkOption {
        type = types.path;
      };
      name = mkOption {
        type = types.str;
        default = name;
        description = ''
          The name of the libvirt domain
        '';
      };
      memory = mkOption {
        default = 128;
        type = types.int;
        description = "The amount of memory in MB";
      };
      uuid = mkOption {
        default = mkUUID cfg.name;
        type = types.string;
      };
      fileShares = mkOption {
        type = with types; attrsOf (submodule {
          options = {
            guestPath = mkOption {
              type = types.str;
            };
            hostPath = mkOption {
              type = types.str;
            };
            neededForBoot = mkOption {
              type = types.bool;
              default = false;
            };
            readOnly = mkOption {
              type = types.bool;
              default = true;
            };
            accessMode = mkOption {
              type = types.enum [ "passthrough" "mapped" "squash" ];
              default = "passthrough";
            };
          };
        });
      };
      netdevs = mkOption {
        default = {};
        type = with types; attrsOf (submodule ({name, ...}: {
          options = {
            network = mkOption {
              type = types.str;
              default = "default";
            };
            mac = mkOption {
              type = types.str;
              default = mkMAC "netdev-${name}-${sys}";
            };
            uuid = mkOption {
              type = types.str;
              default = mkUUID "netdev-${name}-${sys}";
            };
          };
        }));
      };
    };
  };

  config = {

    libvirt.xmlFile = pkgs.writeText "libvirt-${cfg.name}.xml" config.libvirt.xml;

    libvirt.fileShares.nixstore = {
      hostPath = "/nix/store";
      guestPath = "/nix/store";
      neededForBoot = true;
    };

    nixos.modules = singleton {
      boot = {
        kernelParams = [ "logo.nologo" ];
        initrd.kernelModules = [ "9p" "virtio_pci" "9pnet_virtio" ];
        kernelModules = [ "virtio_net" ];
        loader.grub.enable = false;
        vesa = false;
      };

      fileSystems = mkMerge (
        singleton {
          "/" = {
            fsType = "tmpfs";
            device = "tmpfs";
            options = "mode=0755";
          };
        } ++ mapAttrsToList (id: share: {
          "${share.guestPath}" = {
            fsType = "9p";
            device = id;
            inherit (share) neededForBoot;
            options = concatStringsSep "," [
              "trans=virtio"
              "version=9p2000.L"
              (if share.readOnly then "ro" else "rw")
            ];
          };
        }) config.libvirt.fileShares
      );
    };

  };
}
