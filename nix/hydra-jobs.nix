{ config, lib, pkgs, ... }:

with lib;

let

  inputOpts = { ... }: {
    options = {
      type = mkOption {
        type = types.str; # not an enum since Hydra plugins can add new types
        default = "git";
      };
      emailresponsible = mkOption {
        type = types.bool;
        default = false;
      };
      value = mkOption {
        type = types.str;
      };
    };
  };

  jobsetOpts = { name, ... }: {
    options = {
      description = mkOption {
        type = types.str;
        default = "";
      };
      enabled = mkOption {
        type = types.bool;
        default = true;
      };
      hidden = mkOption {
        type = types.bool;
        default = false;
      };
      nixexprinput = mkOption {
        type = types.str;
      };
      nixexprpath = mkOption {
        type = types.str;
      };
      checkinterval = mkOption {
        type = types.int;
        default = 300;
      };
      schedulingshares = mkOption {
        type = types.int;
        default = 100;
      };
      enableemail = mkOption {
        type = types.bool;
        default = false;
      };
      emailoverride = mkOption {
        type = types.str;
        default = "";
      };
      keepnr = mkOption {
        type = types.int;
        default = 3;
      };
      inputs = mkOption {
        type = with types; attrsOf (submodule inputOpts);
        default = {};
      };
    };
  };

in {
  options.hydra = {
    jobsetsJSON = mkOption {
      type = types.package;
    };

    jobsets = mkOption {
      type = with types; attrsOf (submodule jobsetOpts);
    };
  };

  config.hydra.jobsetsJSON = pkgs.writeText "jobsets.json" (
    builtins.toJSON (mapAttrs (_: jobset: {
      enabled = if jobset.enabled then 1 else 0;
      inputs = mapAttrs (_: input: {
        inherit (input) type emailresponsible value;
      }) jobset.inputs;
      inherit (jobset) description hidden nixexprinput nixexprpath checkinterval
        schedulingshares enableemail emailoverride keepnr;
    }) config.hydra.jobsets)
  );
}
