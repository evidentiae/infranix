{ config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

let

  cfg = config.nixos-multi-spawn;

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
    ../resources/nixos-hosts.nix
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

      configFile = mkOption {
        type = types.package;
      };

    };
  };

  config = {
    resources.nixos.commonNixosImports = singleton {
      boot.isContainer = true;
    };

    nixos-multi-spawn = {
      initScript = ''
        test -n "$IP" && \
          ${iproute}/bin/ip addr add $IP dev host0 && \
          ${iproute}/bin/ip link set dev host0 up
      '';

      machines = mapAttrs (name: host: {
        nixosSystem = host.nixos.out.system;
      }) config.resources.nixos.hosts;

      configFile = writeText "nms.json" (toJSON {
        inherit (cfg) tailFiles;
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
