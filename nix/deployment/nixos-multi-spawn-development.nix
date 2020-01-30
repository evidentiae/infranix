{ paths, config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

let

  inherit (config) name;
  inherit (config.nixosHosts) hosts;
  cfg = config.nixos-multi-spawn;

  serviceDef = writeTextDir "${name}.service" ''
    [Service]
    Environment="LOCALE_ARCHIVE=${glibcLocales}/lib/locale/locale-archive"
    Environment="TZDIR=${tzdata}/share/zoneinfo"
    PrivateTmp=true
    Type=notify
    NotifyAccess=all
    ExecStart=${writeScript "nixos-multi-spawn-client" ''
      #!${stdenv.shell}
      cd /tmp
      exec ${nixos-multi-spawn-client}/bin/nixos-multi-spawn-client \
        ${cfg.configFile} ${config.nixosHosts.networking.network}
    ''}
  '';

in {

  imports = [
    ../named.nix
    ../nixos-multi-spawn.nix
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
        systemctl --user enable --runtime --now --quiet \
          "${serviceDef}/${name}.service"

        if ! systemctl --user is-active --quiet "${name}"; then
          echo >&2 "Failed starting service ${name}"
          exit 1
        else
          echo >&2 "Started service ${name}"
        fi
      '';
    };
  };

  cli.commands.destroy.steps = {
    destroy = {
      binary = writeScript "destroy" ''
        #!${stdenv.shell}
        if systemctl --user is-active --quiet "${name}.service"; then
          systemctl --user stop "${name}.service"
        fi
        systemctl --user --runtime disable --quiet \
          "${name}.service" 2>/dev/null || true
      '';
    };
  };
}
