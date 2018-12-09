{ paths, config, lib, pkgs, ... }:

with lib;

let

  topConfig = config;

  cfg = config.resources.nixos;

  hostOpts = { name, config, ... }: {
    imports = cfg.commonHostImports ++ [
      ../named.nix
    ];

    options = {
      ssh = {
        address = mkOption {
          type = with types; either str path;
        };
        extraArgs = mkOption {
          type = with types; listOf str;
          default = [];
        };
      };
      nixos = {
        store.ssh = {
          address = mkOption {
            type = with types; either str path;
            default = config.ssh.address;
          };
          extraArgs = mkOption {
            type = with types; listOf str;
            default = config.ssh.extraArgs;
          };
        };
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
      inherit name;
      nixos = {
        imports = cfg.commonNixosImports;
        baseImports = cfg.commonBaseImports;
        out =
          let
            pkgsModule = { lib, ... }: {
              nixpkgs.pkgs = topConfig.nixpkgs.pkgs;
            };
            eval = (import "${pkgs.path}/nixos/lib/eval-config.nix") ({
              specialArgs.paths = paths;
              modules = config.nixos.imports ++ [ pkgsModule ];
            } // optionalAttrs (config.nixos.baseImports != null) {
              baseModules = config.nixos.baseImports;
            });
          in {
            inherit (eval) config options;
            system = eval.config.system.build.toplevel;
          };
        };
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
