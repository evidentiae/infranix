{ config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

with import ../../lib/integer.nix;
with import ../../lib/ipv4.nix;

let

  inherit (config.resources.nixos) hosts;
  inherit (config) name;

  cfg = config.nixos-multi-spawn;

  inherit (splitCIDR cfg.networking.network) network prefix;

  ipMap = mapAttrs (h: _:
    ipAddressOfHost network prefix (1 + random (name+h) (hostCount prefix - 1))
  ) hosts;

  machineOpts = { name, config, ... }: {
    options = {
      environment = mkOption {
        type = with types; attrsOf str;
        default = {};
      };
      inheritEnvVars = mkOption {
        type = with types; listOf str;
        default = [];
      };
      nixosSystem = mkOption {
        type = types.package;
      };
    };
  };

in {
  imports = [
    ../resources/nixos-hosts
    ../named.nix
  ];

  options = {
    nixos-multi-spawn = {

      initScript = mkOption {
        type = types.lines;
      };

      tailFiles = mkOption {
        type = with types; listOf str;
        default = [];
      };

      machines = mkOption {
        type = with types; attrsOf (submodule machineOpts);
        default = {};
      };

      zone = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          Network zone name passed to systemd-nspawn (see its --network-zone
          parameter).  If null, a unique identifier is generated.
        '';
      };

      configFile = mkOption {
        type = types.package;
      };

      networking = {
        network = mkOption {
          type = types.str;
          default = "10.10.10.0/24";
          description = ''
            The network (in CIDR format) used for the systemd-nspawn containers.
          '';
        };
      };
    };

    resources.nixos.hosts = mkOption {
      type = with types; attrsOf (submodule ({name, ...}: {
        config = {
          addresses.internal = [ name ];
          nixos.store.ssh.address = "localhost";
          ssh.address = ipMap.${name};
        };
      }));
    };
  };

  config = {
    resources.nixos.commonHostImports = [
      ../addressable.nix
    ];

    resources.nixos.commonNixosImports = singleton ({config,...}: {
      boot.isContainer = true;

      networking = {
        useDHCP = false;
        defaultGateway = minHostAddress network prefix;
        hosts = mapAttrs' (h: ip:
          nameValuePair ip hosts.${h}.addresses.internal
        ) ipMap;
      };

      # Disable remount for specialfs
      # For some reason, remounts seems to be forbidden for
      # some special filesystems when systemd-nspawn runs with private user
      # namespace. Needs to investigate if this can be fixed in upstream
      # nixpkgs. The script below is copied from nixpkgs and changed slightly
      # (return 0 when fs is already mounted)
      system.activationScripts.specialfs = mkForce ''
        specialMount() {
          local device="$1"
          local mountPoint="$2"
          local options="$3"
          local fsType="$4"
          local allowRemount="$5"

          if mountpoint -q "$mountPoint"; then
            return 0
          else
            mkdir -m 0755 -p "$mountPoint"
          fi
          mount -t "$fsType" -o "$options" "$device" "$mountPoint"
        }
        source ${config.system.build.earlyMountScript}
      '';
    });

    nixos-multi-spawn = {
      initScript = ''
        test -n "$IP" && \
          ${iproute}/bin/ip addr add $IP dev host0 && \
          ${iproute}/bin/ip link set dev host0 up
      '';

      machines = mapAttrs (name: host: {
        nixosSystem = host.nixos.out.system;
        environment.IP = "${ipMap.${name}}/${toString prefix}";
      }) config.resources.nixos.hosts;

      configFile = writeText "nms.json" (toJSON {
        inherit (cfg) tailFiles zone;
        machines = mapAttrs (_: m: {
          inherit (m) environment inheritEnvVars nixosSystem;
        }) cfg.machines;
        initBinary = writeScript "init" ''
          #!${stdenv.shell}
          ${cfg.initScript}
          exec "$@"
        '';
      });
    };

  };

}
