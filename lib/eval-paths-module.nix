{ paths
, configuration
}:

with builtins;

let

  pathAttrs = if isAttrs paths then paths else import paths;

  lib = import "${pathAttrs.nixpkgs}/lib";

  pkgsModule = { lib, config, ... }: {
    nixpkgs.system = lib.mkDefault currentSystem;
    nixpkgs.pkgs = lib.mkDefault (
      import pathAttrs.nixpkgs {
        inherit (config.nixpkgs) config overlays localSystem crossSystem;
      }
    );
  };

  eval = lib.evalModules {
    specialArgs.paths = pathAttrs;
    modules = [
      configuration
      pkgsModule
      # We reuse this module from NixOS to be able to set nixpkgs modularily
      "${pathAttrs.nixpkgs}/nixos/modules/misc/nixpkgs.nix"
    ];
  };

in eval
