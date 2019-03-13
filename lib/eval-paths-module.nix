{ paths
, configuration
, evaluator ? (x: x)
}:

let

  pkgsModule = { paths, lib, config, ... }: {
    imports = [ (paths.nixpkgs + "/nixos/modules/misc/nixpkgs.nix") ];
    nixpkgs.system = lib.mkDefault builtins.currentSystem;
    nixpkgs.pkgs = lib.mkDefault (
      import paths.nixpkgs {
        inherit (config.nixpkgs) config localSystem crossSystem;
      }
    );
  };

  paths' = import ./eval-paths.nix paths;

in evaluator (
  (import (paths'.nixpkgs + "/lib")).evalModules {
    specialArgs.paths = paths';
    modules = [
      configuration
      pkgsModule
    ];
  }
)
