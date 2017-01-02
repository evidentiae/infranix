{ options, config, lib, pkgs, ... }:

with lib;
with builtins;

let

  cfg = config.export;

  filteredAttrs = setAttrByPath cfg.prefix (
    recursiveUpdate (filterAttrs [] config) cfg.extraConfig
  );

  isPrefixOf = xs: ys: take (length xs) ys == xs;

  includeAttr = path:
    path != [] &&
    any (inc: isPrefixOf inc path) cfg.includeConfig &&
    !(any (exc: isPrefixOf exc path) cfg.excludeConfig) &&
    last path != "_module";

  filterAttrs = path: attrs:
    let names = filter (n: includeAttr (path ++ [n])) (attrNames attrs); in
      listToAttrs (map (n: nameValuePair n (
        let
          v = attrs.${n};
        in
          if !(isAttrs v) || isDerivation v then v
          else filterAttrs (path ++ [n]) v
      )) names);

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
      };

    };

  };

  config = {

    export.build.nixosConfig = { ... }: {
      options = mapAttrs (_: _: mkOption {
        type = types.attrs;
      }) filteredAttrs;

      config = filteredAttrs;
    };

    export.build.jsonFile = pkgs.writeText "config.json" (
      toJSON (filterAttrsRecursive (_: v: !(isFunction v)) filteredAttrs)
    );

  };
}
