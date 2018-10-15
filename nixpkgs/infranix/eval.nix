{ paths
, configuration
, lib ? import "${paths.nixpkgs}/lib"
}:

with builtins;

let

  pkgsModule = { lib, config, ... }: {
    nixpkgs.system = lib.mkDefault currentSystem;
    nixpkgs.pkgs = lib.mkDefault (
      import paths.nixpkgs {
        inherit (config.nixpkgs) config overlays localSystem crossSystem;
      }
    );
  };

  eval = lib.evalModules {
    specialArgs.paths = paths;
    modules = [
      configuration
      pkgsModule
      # We reuse this module from NixOS to be able to set nixpkgs modularily
      "${paths.nixpkgs}/nixos/modules/misc/nixpkgs.nix"
    ];
  };
      
in eval
