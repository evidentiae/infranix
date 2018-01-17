{ config, lib, ... }:

with lib;

{
  options = {
    regions = mkOption {
      apply = unique;
      default = [];
      type = with types; listOf (enum [
        "us-west"
        "us-central"
        "us-east"
        "ca-west"
        "ca-central"
        "ca-east"
        "eu-west"
        "asia-east"
        "asia-southeast"
        "asia-northwest"
      ]);
    };
  };
}
