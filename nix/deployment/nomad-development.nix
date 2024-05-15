{ paths, config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

let

  nomadJob = config.nixos-nomad.jobDefinition;

in {
  imports = [
    ../nixos-nomad.nix
    ../cli.nix
    ./nixos-hosts.nix
    ./nixos-hosts-ssh-no-pwd.nix
  ];

  cli.commands.provision.steps = {
    destroy = {
      inherit (config.cli.commands.destroy.steps.destroy) binary;
    };
    provision = {
      dependencies = [ "destroy" ];
      binary = writeScript "provision" ''
        #!${stdenv.shell}
        nomad run -var extra-bind-mounts="$EXTRA_BIND_MOUNTS" "${nomadJob}"
      '';
    };
  };

  cli.commands.destroy.steps = {
    destroy = {
      binary = writeScript "destroy" ''
        #!${stdenv.shell}
        nomad stop "${config.name}" || true
      '';
    };
  };
}
