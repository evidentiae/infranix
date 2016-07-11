{ config, pkgs, lib, ... }:

with lib;
with builtins;

{
  options = {
    nixos = {
      modules = mkOption {
        type = with types; listOf unspecified;
        default = [];
        description = ''
          A list of NixOS modules defining the configuration of this instance
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
        import "${toString pkgs.path}/nixos" {
          configuration = {
            imports = config.nixos.modules;
          };
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
            imports = config.nixos.modules;
          };
        }
      );
  };
}
