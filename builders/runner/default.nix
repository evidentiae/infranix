{ config, pkgs, lib, ... }:

with lib;

{
  imports = [
    ./impl-make.nix
  ];

  options = {
    runner = {
      out = mkOption {
        type = types.path;
        description = ''
          The top-level binary that runs the defined commands. The first argument
          the binary should be the name of the command you want to run. The rest
          of the arguments will usually be propagated to all of the command's
          sub-steps.
        '';
      };
      backend = mkOption {
        type = types.str;
        default = "make";
        description = ''
          Specifies which backend that should be used for executing the commands
        '';
      };
      commands = mkOption {
        type = with types; attrsOf (listOf (listOf path));
        default = {};
        description = ''
          Each attribute defines one runnable command. Each command is
          defined by a nested list of paths to run. Paths in the inner
          lists represents groups of scripts to run, and each group will
          in parallel. The group themselves will be executed sequentially,
          in the order they appear in the outer list.
        '';
      };
    };
  };
}
