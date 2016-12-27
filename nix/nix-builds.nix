{ config, lib, pkgs, ... }:

with lib;
with pkgs;

let

  buildOpts = { ... }: {
    options = {
      description = mkOption {
        type = types.str;
      };
      nixPath.top = mkOption {
        type = types.str;
      };
      nixPath.sub = mkOption {
        type = types.str;
      };
    };
  };

in {
  imports = [ ./cli.nix ];

  options.nixBuilds = mkOption {
    type = with types; attrsOf (submodule buildOpts);
    default = {};
  };

  config.cli.commands.build.subCommands = mapAttrs (name: build: {
    binary = writeScript "build-${name}" ''
      #!${stdenv.shell}
      exec ${nix}/bin/nix-build '<${build.nixPath.top}/${build.nixPath.sub}>' \
        "$@"
    '';
  }) config.nixBuilds;
}
