{ paths, config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

with import ../../lib/integer.nix;
with import ../../lib/ipv4.nix;

let

  
  inherit (config.resources.nixos) hosts;
  inherit (config) name;

  cfg = config.nixos-multi-nspawn;

  inherit (splitCIDR cfg.networking.network) network prefix;

  ipMap = mapAttrs (h: _:
    ipAddressOfHost network prefix (1 + random (name+h) (hostCount prefix - 1))
  ) hosts;

  serviceDef = writeTextDir "${name}.service" ''
    [Service]
    Environment="LOCALE_ARCHIVE=${glibcLocales}/lib/locale/locale-archive"
    Environment="TZDIR=${tzdata}/share/zoneinfo"
    PrivateTmp=true
    Type=notify
    NotifyAccess=all
    ExecStart=${writeScriptBin "nixos-multi-spawn-client" ''
      #!${stdenv.shell}
      cd /tmp
      exec /run/current-system/sw/bin/nixos-multi-spawn-client \
        ${config.nixos-multi-spawn.configFile} ${cfg.networking.network}
    ''}/bin/nixos-multi-spawn-client
  '';

  dnsmasqHostsFile = writeText "hosts" (concatStrings (
    mapAttrsToList (name: host: concatMapStrings (addr: ''
      ${ipMap.${name}} ${addr}
    '') host.addresses.external) hosts
  ));

in {

  imports = [
    ./default.nix
    ../resources/nixos-hosts.nix
    ../cli.nix
  ];

  options = {
    resources.nixos.hosts = mkOption {
      type = with types; attrsOf (submodule ({name, ...}: {
        config = {
          addresses.internal = [ name ];
          nixos.store.ssh.address = "localhost";
          ssh.address = ipMap.${name};
          ssh.extraArgs = [
            "-q"
            "-o PreferredAuthentications=password"
            "-o StrictHostKeyChecking=no"
            "-o UserKnownHostsFile=/dev/null"
          ];
        };
      }));
    };

    nixos-multi-nspawn.networking = {
      dns.hostsDir = mkOption {
        type = with types; nullOr path;
        description = ''
          The path to writeable directory where NetworkManager checks for new
          hosts files.
        '';
      };
  
      network = mkOption {
        type = types.str;
        default = "10.10.10.0/24";
        description = ''
          The network (in CIDR format) used for the systemd-nspawn containers.
        '';
      };
    };
  };

  config = {

    nixos-multi-spawn = {
      machines = mapAttrs (name: host: {
        environment.IP = "${ipMap.${name}}/16";
      }) hosts;
    };

    resources.nixos.commonHostImports = [
      ../addressable.nix
    ];

    resources.nixos.commonNixosImports = singleton ({config,...}: {
      networking = {
        useDHCP = false;
        defaultGateway = minHostAddress network prefix;
        hosts = mapAttrs' (h: ip:
          nameValuePair ip hosts.${h}.addresses.internal
        ) ipMap;
      };

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
