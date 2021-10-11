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
        GIT_REPO="$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null || echo "")"
        nomad run -var git-repo="$GIT_REPO" "${nomadJob}"
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
