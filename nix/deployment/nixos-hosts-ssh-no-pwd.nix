{ paths, config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

{

  imports = [
    ../nixos-hosts.nix
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
  };
}
