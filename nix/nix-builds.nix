{ paths, config, lib, pkgs, ... }:

with lib;
with pkgs;

let

  buildOpts = { config, ... }: {
    options = {
      enabled = mkOption {
        type = types.bool;
        default = true;
      };
      description = mkOption {
        type = types.str;
      };
      nixExprInput = mkOption {
        type = types.enum (attrNames paths);
      };
      nixExprPath = mkOption {
        type = types.str;
      };
      nixPath = mkOption {
        type = with types; attrsOf str;
        default = {};
      };
      args = mkOption {
        type = with types; attrsOf str;
        default = {};
      };
      argStrings = mkOption {
        type = with types; attrsOf str;
        default = {};
      };
      options = mkOption {
        type = with types; listOf str;
        default = [];
      };
      clearNixPath = mkOption {
        type = types.bool;
        default = true;
      };
      inheritedPaths = mkOption {
        type = with types; listOf (enum (attrNames paths));
      };
    };
    config = {
      inheritedPaths = [ config.nixExprInput ];
      args.paths = mkIf (paths._pathsFile != null) (mkDefault paths._pathsFile);
      nixPath = genAttrs config.inheritedPaths (p: "${toString paths.${p}}");
    };
  };

in {
  imports = [ ./cli.nix ];

  options.nixBuilds = mkOption {
    type = with types; attrsOf (submodule buildOpts);
    default = {};
  };

#  config.cli.commands.build.subCommands = mapAttrs (name: build: {
#    binary = writeScript "build-${name}" ''
#      #!${stdenv.shell}
#      nix="$(type -P nix)"
#      if [ -z "$nix" ]; then
#        echo >&2 "nix not found in PATH, can't run build"
#        exit 1
#      fi
#
#      ${optionalString build.clearNixPath "export NIX_PATH="}
#
#      exec "$nix" build \
#        -f "<${build.nixExprInput}/${build.nixExprPath}>" \
#        ${concatStringsSep " " build.options} \
#        ${concatStringsSep " " (
#            mapAttrsToList (k: v: "--arg '${k}' '${v}'") build.args
#        )} \
#        ${concatStringsSep " " (
#            mapAttrsToList (k: v: "--argstr '${k}' '${v}'") build.argStrings
#        )} \
#        ${concatStringsSep " " (
#            mapAttrsToList (k: v: "-I '${k}=${v}'") build.nixPath
#        )} \
#        "$@"
#    '';
#  }) config.nixBuilds;
}
