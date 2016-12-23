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

      nixos.hosts = mkOption {
        description = "NixOS hosts";
        type = with types; attrsOf (submodule hostOpts);
        default = {};
      };

    };

  };

}
