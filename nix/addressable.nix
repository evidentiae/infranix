{ config, lib, ... }:

with lib;
with builtins;

let

  allAddresses = config.addresses.internal ++ config.addresses.external;

  defaultAddress =
    if allAddresses != [] then head allAddresses
    else throw "${config.name}: No address defined";


in {
  imports = [ ./named.nix ];

  options = {
    addresses = {
      external = mkOption {
        type = with types; listOf str;
        default = [];
      };
      internal = mkOption {
        type = with types; listOf str;
        default = [];
      };
      default = mkOption {
        type = types.str;
      };
    };
  };

  config = {
    addresses.default = mkForce defaultAddress;
  };
}
