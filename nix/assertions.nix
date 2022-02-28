# Copied from NixOS

{ config, lib, pkgs, ... }:

with lib;

{

  options = {

    withAssertions = mkOption {
      type = types.unspecified;
    };

  };

  config = {

    withAssertions = x:
      let
        failed = map (x: x.message) (filter (x: !x.assertion) config.assertions);
        showWarnings = res: fold (w: x:
          builtins.trace "[1;31mwarning: ${w}[0m" x
        ) res config.warnings;
      in showWarnings (
        if [] == failed then x
        else throw "\nFailed assertions:\n${concatStringsSep "\n" (map (x: "- ${x}") failed)}"
      );

  };

}
