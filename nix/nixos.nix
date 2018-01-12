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
        type = with types; nullOr (listOf path);
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
      let
        args = {
          system = builtins.currentSystem;
          modules = [ { inherit (config.nixos) imports; } ];
        } // optionalAttrs (config.nixos.baseImports != null) {
          baseModules = config.nixos.baseImports;
        };

        eval = import "${toString pkgs.path}/nixos/lib/eval-config.nix" args;
      in {
        inherit (eval) config options;
        system = eval.config.system.build.toplevel;
      };
  };
}
