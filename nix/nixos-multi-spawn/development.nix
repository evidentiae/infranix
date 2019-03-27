{ paths, config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

let

  inherit (config.resources.nixos) hosts;
  inherit (config) name;

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
        ${cfg.configFile} ${cfg.networking.network}
    ''}
  '';

  dnsmasqHostsFile = writeText "hosts" (concatStrings (
    mapAttrsToList (name: host: concatMapStrings (addr: ''
      ${host.ssh.address} ${addr}
    '') host.addresses.external) hosts
  ));

in {

  imports = [
    ./default.nix
    ../resources/nixos-hosts
    ../cli.nix
  ];

  options = {
    resources.nixos.hosts = mkOption {
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

    nixos-multi-spawn.networking.dns.hostsDir = mkOption {
      type = with types; nullOr path;
      description = ''
        The path to writeable directory where NetworkManager checks for new
        hosts files.
      '';
    };
  };

  config = {
    resources.nixos.commonNixosImports = singleton ({config,...}: {
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
      dns = mkIf (cfg.networking.dns.hostsDir != null) {
        binary = writeScript "deploy-dns" ''
          #!${stdenv.shell}
          d="${cfg.networking.dns.hostsDir}"
          if [ -w "$d" ] || [ -w "$(dirname "$d")" ]; then
            echo >&2 "Configuring DNS in $d"
            mkdir -p "$d"
            cp -fT ${dnsmasqHostsFile} "$d/${name}"
            chmod u+w "$d/${name}"
          else
            echo >&2 "Skipping DNS configuration, $d not writeable"
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
          systemctl --user disable --quiet \
            "${name}.service" 2>/dev/null || true
        '';
      };
      dns = mkIf (cfg.networking.dns.hostsDir != null) {
        binary = writeScript "destroy-dns" ''
          #!${stdenv.shell}
          d="${cfg.networking.dns.hostsDir}"
          if [ -w "$d/${name}" ]; then
            truncate -s 0 -c "$d/${name}"
            rm -f "$d/${name}"
          fi
        '';
      };
    };
  };
}
