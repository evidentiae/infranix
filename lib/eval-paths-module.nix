{ paths
, configuration
, evaluator ? (x: x)
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
  } else if t == "set" && paths ? type && paths.type == "derivation" then rec {
    pathsFile = toString paths;
    pathAttrs = import pathsFile;
  } else if t == "set" && paths ? outPath then rec {
    pathsFile = toString paths;
    pathAttrs = import pathsFile;
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
        if t == "string" then
          { path = p; pathRef = p; }
        else if t == "path" then
          let p' = toString p; in {
            path = p';
            pathRef = p';
          }
        else if t == "set" && p ? url then
          let p' = fetchGit p; in {
            path = toString p';
            pathRef = p // { inherit (p') rev; };
          }
        else throw "path attribute ${name} has an unsupported type";
    };

  lib = import "${pathAttrs'.nixpkgs.path}/lib";

  pkgsModule = { lib, config, ... }: {
    nixpkgs.system = lib.mkDefault currentSystem;
    nixpkgs.pkgs = lib.mkDefault (
      import pathAttrs'.nixpkgs.path {
        inherit (config.nixpkgs) config overlays localSystem crossSystem;
      }
    );
  };

in evaluator (
  lib.evalModules {
    specialArgs.paths = lib.mapAttrs (_: p: p.path) pathAttrs';
    specialArgs.pathRefs = lib.mapAttrs (_: p: p.pathRef) pathAttrs';
    specialArgs.pathsFile = pathsFile;
    modules = [
      configuration
      pkgsModule
      # We reuse this module from NixOS to be able to set nixpkgs modularily
      "${pathAttrs'.nixpkgs.path}/nixos/modules/misc/nixpkgs.nix"
    ];
  }
)
