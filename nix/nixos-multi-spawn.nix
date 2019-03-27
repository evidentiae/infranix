{ config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

let

  inherit (config.nixosHosts) hosts;

  cfg = config.nixos-multi-spawn;

in {
  imports = [
    ./nixos-containers.nix
  ];

  options = {
    nixos-multi-spawn = {
      initScript = mkOption {
        type = types.str;
        default = ''
          test -n "$IP" && \
            ${iproute}/bin/ip addr add $IP dev host0 && \
            ${iproute}/bin/ip link set dev host0 up
        '';
      };

      tailFiles = mkOption {
        type = with types; listOf str;
        default = [];
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
    };
  };

  config = {
    nixos-multi-spawn.configFile = writeText "nms.json" (toJSON {
      inherit (cfg) tailFiles zone;
      machines = mapAttrs (_: h: {
        inherit (h) environment;
        inheritEnvVars = [];
        nixosSystem = h.nixos.out.system;
      }) hosts;
      initBinary = writeScript "init" ''
        #!${stdenv.shell}
        ${cfg.initScript}
        exec "$@"
      '';
    });
  };
}
