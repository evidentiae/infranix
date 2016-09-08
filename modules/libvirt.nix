{ name, config, pkgs, lib, ... }:

with lib;
with builtins;

let

  cfg = config.libvirt;

  inherit (import ../lib.nix) mkUUID mkMAC;

  sys = config.nixos.out.system;

  mkFsOptions = list:
    if versionAtLeast lib.nixpkgsVersion "16.09" then list
    else concatStringsSep "," list;

  ifLxc = optionalString (cfg.backend == "lxc");
  ifQemu = optionalString (cfg.backend == "qemu");

  libvirtDevices = [
    (ifLxc "<emulator>${pkgs.libvirt}/libexec/libvirt_lxc</emulator>")
    (ifQemu "<memballoon model='virtio'/>")
    (if cfg.consoleFile == null
      then "<serial type='pty'><target port='0'/></serial>"
      else ''
        <serial type='file'>
          <source path='${cfg.consoleFile}'/>
          <target port='0'/>
        </serial>
      ''
    )
    (ifLxc "<console type='pty'><target port='0'/></console>")
    (concatStrings (mapAttrsToList (n: dev: ''

      <interface type='network'>
        ${ifQemu "<model type='virtio'/>"}
        <source network='${dev.network}'/>
        ${optionalString (dev.mac != null)
          "<mac address='${dev.mac}'/>"
        }
      </interface>
    '') cfg.netdevs))
    (concatStrings (mapAttrsToList (n: share: ''
      <filesystem type='mount' ${ifQemu "accessmode='${share.accessMode}'"}>
        <source dir='${
          (optionalString (substring 0 1 share.hostPath != "/") "@pwd@/") +
          share.hostPath
        }'/>
        <target dir='${if cfg.backend == "qemu" then n else share.guestPath}'/>
        ${ifQemu (optionalString share.readOnly "<readonly/>")}
      </filesystem>
    '') cfg.fileShares))
    cfg.extraDevices
  ];

  libvirtQemuDomain = ''
    <domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
      <name>${cfg.name}</name>
      ${optionalString (cfg.uuid != null) "<uuid>${cfg.uuid}</uuid>"}
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

  libvirtLxcDomain = ''
    <domain type='lxc'>
      <name>${cfg.name}</name>
      ${optionalString (cfg.uuid != null) "<uuid>${cfg.uuid}</uuid>"}
      <memory unit='M'>${toString cfg.memory}</memory>
      <currentMemory unit='M'>${toString cfg.memory}</currentMemory>
      <vcpu placement='static'>${toString cfg.cpuCount}</vcpu>
      <os>
        <type>exe</type>
        <init>${sys}/init</init>
      </os>
      <features>
        <capabilities policy='default'>
          <mknod state='on'/>
        </capabilities>
      </features>
      <idmap>
        <uid start='0' target='${cfg.lxc.mappedUid}' count='100000'/>
        <gid start='0' target='${cfg.lxc.mappedGid}' count='100000'/>
      </idmap>
      <clock offset='utc'/>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>destroy</on_reboot>
      <on_crash>destroy</on_crash>
      <devices>${concatStrings libvirtDevices}</devices>
    </domain>
  '';

  libvirtDomain = ({
    qemu = libvirtQemuDomain;
    lxc = libvirtLxcDomain;
  }).${cfg.backend};

in {
  imports = [
    ./nixos.nix
  ];

  options = {
    libvirt = {
      backend = mkOption {
        type = types.enum [ "qemu" "lxc" ];
        default = "qemu";
      };

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
        type = with types; nullOr str;
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
      lxc = {
        mappedUid = mkOption {
          type = types.str;
        };
        mappedGid = mkOption {
          type = types.str;
        };
        rootPath = mkOption {
          type = types.str;
        };
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
            mount = mkOption {
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

    libvirt.fileShares.root = mkIf (cfg.backend == "lxc") {
      hostPath = cfg.lxc.rootPath;
      guestPath = "/";
      mount = false;
    };

    nixos.modules = singleton {
      boot = {
        kernelParams = [ "logo.nologo" ];
        initrd.kernelModules = [ "9p" "virtio_pci" "9pnet_virtio" ];
        kernelModules = [ "virtio_net" ];
        loader.grub.enable = false;
        vesa = false;
        isContainer = cfg.backend == "lxc";
      };

      networking.usePredictableInterfaceNames = false;

      i18n.consoleFont = "";

      systemd.services.console-getty.enable = mkIf (cfg.backend == "lxc") false;

      fileSystems = mkIf (cfg.backend != "lxc") (mkMerge (
        singleton {
          "/" = {
            fsType = "tmpfs";
            device = "tmpfs";
            options =  mkFsOptions [ "mode=0755" ];
          };
        } ++ mapAttrsToList (id: share: {
          "${share.guestPath}" = {
            fsType = "9p";
            device = id;
            inherit (share) neededForBoot;
            options = mkFsOptions [
              "trans=virtio"
              "version=9p2000.L"
              (if share.readOnly then "ro" else "rw")
            ];
          };
        }) (filterAttrs (_: s: s.mount) config.libvirt.fileShares)
      ));
    };

  };
}
