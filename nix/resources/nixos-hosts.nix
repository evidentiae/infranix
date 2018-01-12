{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.resources.nixos;

  hostOpts = {name, ...}: {
    imports = cfg.commonHostImports ++ [
      ../nixos.nix
      ../named.nix
    ];

    options = {};

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
