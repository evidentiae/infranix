{ config, lib, pkgs, ... }:

with lib;
with pkgs;

let

  buildOpts = { ... }: {
    options = {
      enabled = mkOption {
        type = types.bool;
        default = true;
      };
      description = mkOption {
        type = types.str;
      };
      nixPath.top = mkOption {
        type = types.str;
      };
      nixPath.sub = mkOption {
        type = types.str;
      };
      fallback = mkOption {
        type = types.bool;
        default = true;
      };
      arguments = mkOption {
        type = types.attrs;
        default = {};
        description = ''
          Pass arguments to the build definition. If this is used,
          the build definition should be a function taking the
          passed arguments as parameters. Note that the parameters
          are *not* passed if the build is run by Hydra, only when
          the build is run in the CLI. Because of this, all parameters
          of the build definition function should have default values.
          Also note that currently only boolean arguments are supported.
        '';
      };
    };
  };

  passArgs = args: concatStringsSep " " (mapAttrsToList (name: value:
    "--arg ${name} ${if value then "true" else "false"}") args
  );

in {
  imports = [ ./cli.nix ];

  options.nixBuilds = mkOption {
    type = with types; attrsOf (submodule buildOpts);
    default = {};
  };

  config.cli.commands.build.subCommands = mapAttrs (name: build: {
    binary = writeScript "build-${name}" ''
      #!${stdenv.shell}
      nixbuild="$(type -P nix-build)"
      if [ -z "$nixbuild" ]; then
        echo >&2 "nix-build not found in PATH, can't run build"
        exit 1
      fi
      exec "$nixbuild" ${if build.fallback then "--fallback" else ""} \
        '<${build.nixPath.top}/${build.nixPath.sub}>' \
        ${passArgs build.arguments} \
        "$@"
    '';
  }) config.nixBuilds;
}
