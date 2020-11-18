{ config, lib, pkgs, ... }:

with lib;
with pkgs;
with builtins;

with import ../lib/integer.nix;
with import ../lib/ipv4.nix;

let

  inherit (config.nixosHosts) hosts networking;
  inherit (splitCIDR networking.network) network prefix;

  ipMap = mapAttrs (h: _:
    ipAddressOfHost network prefix (1 + random h (hostCount prefix - 1))
  ) hosts;

in {
  imports = [
    ./nixos-hosts.nix
  ];

  options = {
    nixosHosts = {
      networking = {
        network = mkOption {
          type = types.str;
          default = "10.10.10.0/24";
          description = ''
            The network (in CIDR format) used for the containers.
          '';
        };
      };

      hosts = mkOption {
        type = with types; attrsOf (submodule ({name, ...}: {
          options = {
            environment = mkOption {
              type = with types; attrsOf str;
              default = {};
            };
          };
          config = {
            addresses.internal = [ name ];
            nixos.store.ssh.address = "localhost";
            ssh.address = ipMap.${name};
            environment.IP = "${ipMap.${name}}";
            environment.PREFIX = "${toString prefix}";
          };
        }));
      };
    };
  };

  config = {
    nixosHosts.commonHostImports = [
      ./addressable.nix
    ];

    nixosHosts.commonNixosImports = [
      ../nixos/disable-nix.nix
      ({config,...}: {
        boot.isContainer = true;

        networking = {
          useDHCP = false;
          defaultGateway = minHostAddress network prefix;
          hosts = mapAttrs' (h: ip:
            nameValuePair ip (with hosts.${h}.addresses; internal ++ external)
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
      })
    ];
  };
}
