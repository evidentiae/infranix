{ paths
, configuration
}:

with builtins;

with (
  let t = typeOf paths;
  in if t == "string" then {
    pathsFile = paths;
    pathAttrs = import paths;
  } else if t == "path" then {
    pathsFile = toString paths;
    pathAttrs = import paths;
  } else if t == "set" then {
    pathsFile = null;
    pathAttrs = paths;
  } else throw "paths argument has wrong type"
);

let

  pathAttrs' = listToAttrs (map evalPath (attrNames pathAttrs));

  evalPath = name:
    let
      p = pathAttrs.${name};
      t = typeOf p;
    in {
      inherit name;
      value =
        if t == "string" then p
        else if t == "path" then toString p
        else if t == "set" && p ? url then toString (fetchGit p)
        else throw "path attribute ${name} has an unsupported type";
    };

  lib = import "${pathAttrs'.nixpkgs}/lib";

  pkgsModule = { lib, config, ... }: {
    nixpkgs.system = lib.mkDefault currentSystem;
    nixpkgs.pkgs = lib.mkDefault (
      import pathAttrs'.nixpkgs {
        inherit (config.nixpkgs) config overlays localSystem crossSystem;
      }
    );
  };

  eval = lib.evalModules {
    specialArgs.paths = pathAttrs';
    specialArgs.pathsFile = pathsFile;
    modules = [
      configuration
      pkgsModule
      # We reuse this module from NixOS to be able to set nixpkgs modularily
      "${pathAttrs'.nixpkgs}/nixos/modules/misc/nixpkgs.nix"
    ];
  };

in eval
