{ name, config, pkgs, lib, ... }:

with lib;
with builtins;

let

  cfg = config.libvirt;

  inherit (import ../lib.nix) mkUUID mkMAC;

  sys = config.nixos.out.system;

  libvirtDevices = [
    "<memballoon model='virtio'/>"
    (if cfg.consoleFile == null
      then "<serial type='pty'><target port='0'/></serial>"
      else ''
        <serial type='file'>
          <source path='${cfg.consoleFile}'/>
          <target port='0'/>
        </serial>
      ''
    )
    (concatStrings (mapAttrsToList (n: dev: ''
      <interface type='network'>
        <model type='virtio'/>
        <source network='${dev.network}'/>
        ${optionalString (dev.mac != null)
          "<mac address='${dev.mac}'/>"
        }
      </interface>
    '') cfg.netdevs))
    (concatStrings (mapAttrsToList (n: share: ''
      <filesystem type='mount' accessmode='${share.accessMode}'>
        <source dir='${
          (optionalString (substring 0 1 share.hostPath != "/") "@pwd@/") +
          share.hostPath
        }'/>
        <target dir='${n}'/>
        ${optionalString share.readOnly "<readonly/>"}
      </filesystem>
    '') cfg.fileShares))
    cfg.extraDevices
  ];

  libvirtDomain = ''
    <domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
      <name>${cfg.name}</name>
      <uuid>${cfg.uuid}</uuid>
      <memory unit='M'>${toString cfg.memory}</memory>
      <currentMemory unit='M'>${toString cfg.memory}</currentMemory>
      <vcpu placement='static'>${toString cfg.cpuCount}</vcpu>
      <os>
        <type>hvm</type>
        <kernel>${sys}/kernel</kernel>
        <initrd>${sys}/initrd</initrd>
        <cmdline>${toString (
          config.nixos.out.config.boot.kernelParams ++ [
            "console=ttyS0" "init=${sys}/init"
          ]
        )}</cmdline>
      </os>
      <features><acpi/></features>
      <cpu><model>kvm64</model></cpu>
      <clock offset='utc'/>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>destroy</on_reboot>
      <on_crash>destroy</on_crash>
      <devices>${concatStrings libvirtDevices}</devices>
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
        default = libvirtDomain;
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
        type = types.str;
      };
      consoleFile = mkOption {
        type = with types; nullOr str;
        default = null;
      };
      extraDevices = mkOption {
        type = types.lines;
        default = "";
      };
      cpuCount = mkOption {
        type = types.int;
        default = 2;
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
              type = with types; nullOr str;
              default = mkMAC "netdev-${name}-${sys}";
            };
          };
        }));
      };
    };
  };

  config = {

    libvirt.xmlFile = pkgs.writeText "libvirt.xml" config.libvirt.xml;

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

      networking.usePredictableInterfaceNames = false;

      i18n.consoleFont = "";

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
