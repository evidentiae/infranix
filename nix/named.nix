{ config, lib, ... }:

with lib;

{
  options = {
    name = mkOption {
      type = types.str;
    };
  };

  config = {};
}
