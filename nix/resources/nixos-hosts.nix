{ paths, config, lib, pkgs, ... }:

with pkgs;
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
        imports = cfg.commonNixosImports ++ singleton {
          networking.hostName = mkDefault name;
        };
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

  imports = [
    ../cli.nix
  ];

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

  config = {

    cli.commands.server.subCommands.info.binary = mkDefault (writeScript "server-info" ''
      #!${stdenv.shell}

      if [ "$#" -lt 2 ]; then
        exit 1
      fi

      function echoOrExec() {
        if [[ "$1" =~ ^/.* ]]; then
          "$1"
        else
          echo "$1"
        fi
      }

      case "$1" in
        ${concatMapStrings (host: ''
          ${host.name}):
            case "$2" in
              ssh_address) echoOrExec "${host.ssh.address}" ;;
              ssh_args) echo "${concatStringsSep " " host.ssh.extraArgs}" ;;
              nixstore_ssh_address) echoOrExec "${host.nixos.store.ssh.address}" ;;
              nixstore_ssh_args) echo "${concatStringsSep " " host.nixos.store.ssh.extraArgs}" ;;
              *) exit 1 ;;
            esac
            ;;
        '') (attrValues cfg.hosts)}
        *)
        echo >&2 "Server $1 does not exist"
        exit 1
        ;;
      esac
    '');

    cli.commands.server.subCommands.shell.binary = writeScript "server-shell" ''
      #!${stdenv.shell}
      set -eu
      set -o pipefail

      server_info=${config.cli.commands.server.subCommands.info.binary}

      if [ "$#" -lt 1 ]; then
        echo >&2 "No server specified"
        exit 1
      fi

      ssh_address="$($server_info "$1" ssh_address)"
      ssh_args="$($server_info "$1" ssh_args)"
      nixstore_ssh_address="$($server_info "$1" nixstore_ssh_address)"
      nixstore_ssh_args="$($server_info "$1" nixstore_ssh_args)"

      shift 1

      if [[ "$nixstore_ssh_address" != localhost ]] && [ "$#" -gt 0 ] && [[ "$1" == "${builtins.storeDir}"* ]]; then
        NIX_SSHOPTS="-lroot $nixstore_ssh_args" \
          nix copy -s --to "ssh://$nixstore_ssh_address" "$1"
      fi

      exec ssh -lroot $ssh_args "$ssh_address" "$@"
    '';

    cli.commands.server.subCommands.shell.completions = singleton (
      concatStringsSep "|" (attrNames cfg.hosts)
    );

  };

}
