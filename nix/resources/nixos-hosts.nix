{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.resources.nixos;

  hostOpts = {name, ...}: {
    imports = cfg.commonHostImports ++ [
      ../nixos.nix
      ../named.nix
    ];

    options = {
      ssh = {
        address = mkOption {
          type = with types; either str path;
        };
        command = mkOption {
          type = types.package;
          default = pkgs.writeScriptBin "ssh" ''
            #!${pkgs.stdenv.shell}
            exec ssh "$@"
          '';
        };
        extraArgs = mkOption {
          type = with types; listOf str;
          default = [];
        };
      };
      nixos = {
        store.ssh = {
          address = mkOption {
            type = with types; either str path;
            default = config.ssh.address;
          };
          command = mkOption {
            type = types.package;
            default = config.ssh.command;
          };
          extraArgs = mkOption {
            type = with types; listOf str;
            default = config.ssh.extraArgs;
          };
        };
      };
    };

    config = {
      _module.args = { inherit pkgs; };
      inherit name;
      nixos.imports = cfg.commonNixosImports;
      nixos.baseImports = cfg.commonBaseImports;
    };
  };

in {

  options = {

    resources = {

      nixos.commonHostImports = mkOption {
        type = with types; listOf unspecified;
        default = [];
      };

      nixos.commonNixosImports = mkOption {
        type = with types; listOf unspecified;
        default = [];
      };

      nixos.commonBaseImports = mkOption {
        type = with types; nullOr (listOf path);
        default = null;
      };

      nixos.hosts = mkOption {
        description = "NixOS hosts";
        type = with types; attrsOf (submodule hostOpts);
        default = {};
      };

    };

  };

}
