{ options, config, lib, pkgs, ... }:

with lib;
with builtins;

let

  cfg = config.export;
  opts = options.export;

  isPrefixOf = xs: ys: take (length xs) ys == xs;

  excludePath = path:
    path == [] ||
    any (exc: isPrefixOf exc path) cfg.excludeConfig;

  includePath = path:
    any (inc: isPrefixOf inc path) cfg.includeConfig;

in {
  options = {

    export = {

      includeConfig = mkOption {
        type = with types; listOf (listOf str);
        default = [];
      };

      excludeConfig = mkOption {
        type = with types; listOf (listOf str);
        default = [];
      };

      extraConfig = mkOption {
        type = types.attrs;
        default = {};
      };

      prefix = mkOption {
        type = with types; listOf str;
        default = [];
      };

      build = {
        nixosConfig = mkOption {
          type = types.unspecified;
          readOnly = true;
        };

        jsonFile = mkOption {
          type = types.package;
          readOnly = true;
        };

        config = mkOption {
          type = types.attrs;
          readOnly = true;
        };

        options = mkOption {
          type = with types; listOf attrs;
          readOnly = true;
        };
      };

    };

  };

  config = {

    export.build.nixosConfig = { ... }: {
      options = mapAttrsRecursiveCond (as: !(isDerivation as)) (_: _: mkOption {
        type = types.unspecified;
        readOnly = true;
      }) cfg.build.config;

      config = cfg.build.config;
    };

    export.build.jsonFile = pkgs.writeText "config.json" (
      toJSON (filterAttrsRecursive (_: v: !(isFunction v)) cfg.build.config)
    );

    export.build.config = foldr recursiveUpdate {} (map (o:
      optionalAttrs o.isDefined (
        let v = getAttrFromPath o.loc config;
        in setAttrByPath o.loc (
          if isAttrs v then filterAttrsRecursive (n: _: n != "_module") v else v
        )
      )
    ) cfg.build.options);

    export.build.options = filter (o:
      !(excludePath o.loc) && includePath o.loc
    ) (collect isOption options);

  };
}
