{ config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

let

  mkScript = prefix: set:
    let
      set' = mapAttrs (n: v: v // {
        text = ''
          echo '[${prefix}:${n}]'
          ${v.text}
        '';
      }) (
        mapAttrs (n: v: if isString v then noDepEntry v else v) set
      );
    in textClosureMap id set' (attrNames set');

  scriptType = with types; attrsOf (either lines (submodule (_: {
    options = {
      text = mkOption {
        type = lines;
        default = "";
      };
      deps = mkOption {
        type = listOf str;
        default = [];
      };
    };
  })));

in {

  options = {
    testing = {
      scriptPath = mkOption {
        type = with types; listOf path;
        default = [];
        description = ''
          The PATH used by testScript and validationScript
        '';
      };

      succeedOnFailure = mkOption {
        type = types.bool;
        default = true;
      };

      testScript = mkOption {
        type = scriptType;
        default = {};
        apply = mkScript "test";
        description = ''
          The main test script. This option is configured like the
          activationScripts option in NixOS. Everything that this script writes
          to its current working directory will end up in the Nix build output.
        '';
      };

      validationScript = mkOption {
        type = scriptType;
        default = {};
        apply = mkScript "validate";
        description = ''
          A separate script executed after the main test script. The validation
          script will run even if the main test script fails, and can be used
          for post-processing. This option is configured like the
          activationScripts option in NixOS. Everything that this script writes
          to its current working directory will end up in the Nix build output.
        '';
      };

      result = mkOption {
        type = types.package;
        description = ''
          The result of the test
        '';
      };
    };
  };

  config = {
    testing.validationScript.setup = ''
      function build-product() {
        mkdir -p nix-support
        echo "$1" >> nix-support/hydra-build-products
      }
    '';
  };
}
