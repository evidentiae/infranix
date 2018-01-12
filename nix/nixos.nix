{ config, pkgs, lib, ... }:

with lib;
with builtins;

{
  options = {
    nixos = {
      imports = mkOption {
        type = with types; listOf unspecified;
        default = [];
        description = ''
          A list of NixOS modules defining the configuration of this instance
        '';
      };
      baseImports = mkOption {
        type = with types; nullOr (listOf string);
        default = null;
        description = ''
          This option overrides the list of module paths that constitute the
          NixOS "base modules", i.e. the modules from the NixOS distribution
          that are implicitly imported and merged into all user-defined NixOS
          modules. An override is typically done to make the list of base
          modules smaller, to increase performance of evaluating custom NixOS
          modules.  If this option is set to `null` (the default value), no
          override is done and the standard list of paths is used (defined in
          `nixos/modules-list.nix` in the nixpkgs repo).
        '';
      };
      pathOverride = mkOption {
        type = with types; nullOr unspecified;
        default = null;
        example = literalExample ''
          paths: paths // {
            nixpkgs = paths.nixpkgs-1412;
            nixpkgs-master = pkgs.fetchgit {
              url = "https://github.com/NixOS/nixpkgs.git";
              rev = "8e6acbe2011be0939eafd4772fcc837f81aaf4fb";
              sha256 = "1hhj9sin6984214vias8p520whmm1fil0a7xvhnapx05xfzaz9vh";
            };
          }
        '';
        description = ''
          This option lets you override the Nix paths used for evaluating the
          NixOS build. It should be set to a function that takes an attribute
          set of prefix/path pairs and returns a new attribute set.
        '';
      };
      out = mkOption {
        type = types.unspecified;
        description = ''
          The resulting NixOS build
        '';
      };
    };
  };

  config = {
    nixos.out =
      if config.nixos.pathOverride == null then
        let
          args = {
            system = builtins.currentSystem;
            modules = [ { inherit (config.nixos) imports; } ];
          } // optionalAttrs (config.nixos.baseImports != null) {
            baseModules = map (s: "${toString pkgs.path}/nixos/modules/${s}") config.nixos.baseImports;
          };

          eval = import "${toString pkgs.path}/nixos/lib/eval-config.nix" args;
        in {
          inherit (eval) config options;
          system = eval.config.system.build.toplevel;
        }
      else (
        let overrides = {
          __nixPath = sort (p1: p2: p1.prefix > p2.prefix) (
            mapAttrsToList (prefix: path: { inherit prefix path; }) (
              config.nixos.pathOverride (
                listToAttrs (map (x: nameValuePair x.prefix x.path) __nixPath)
              )
            )
          );
          import = fn: scopedImport overrides fn;
          scopedImport = attrs: fn: scopedImport (overrides // attrs) fn;
          builtins = builtins // overrides;
        };
        in let inherit (overrides) __nixPath;
        in scopedImport overrides <nixpkgs/nixos> {
          configuration = {
            inherit (config.nixos) imports;
          };
        }
      );
  };
}
