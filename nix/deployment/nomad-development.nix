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
  ];

  options = {
    nixosHosts.hosts = mkOption {
      type = with types; attrsOf (submodule ({name, ...}: {
        config = {
          ssh.extraArgs = [
            "-q"
            "-o PreferredAuthentications=password"
            "-o StrictHostKeyChecking=no"
            "-o UserKnownHostsFile=/dev/null"
          ];
        };
      }));
    };
  };

  config = {
    nixosHosts.commonNixosImports = singleton ({config,...}: {
      users.users.root.password = mkForce "";
      services.openssh = {
        enable = true;
        permitRootLogin = mkForce "yes";
        passwordAuthentication = mkForce true;
        extraConfig = ''
          PermitEmptyPasswords yes
          AuthenticationMethods none
        '';
      };
    });

    cli.commands.provision.steps = {
      destroy = {
        inherit (config.cli.commands.destroy.steps.destroy) binary;
      };
      provision = {
        dependencies = [ "destroy" ];
        binary = writeScript "provision" ''
          #!${stdenv.shell}
          nomad run "${nomadJob}"
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
  };
}
