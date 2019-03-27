{ paths, config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

let

  inherit (config) name;
  inherit (config.nixosHosts) hosts;
  inherit (config.nixosHosts.networking.dns) hostsDir;

  dnsmasqHostsFile = writeText "hosts" (concatStrings (
    mapAttrsToList (name: host: concatMapStrings (addr: ''
      ${host.ssh.address} ${addr}
    '') host.addresses.external) hosts
  ));

in {

  imports = [
    ../named.nix
    ../cli.nix
    ./nixos-hosts.nix
  ];

  options = {
    nixosHosts.networking.dns.hostsDir = mkOption {
      type = with types; nullOr path;
      description = ''
        The path to writeable directory where NetworkManager checks for new
        hosts files.
      '';
    };
  };

  config = {
    cli.commands.provision.steps = {
      dns = mkIf (hostsDir != null) {
        binary = writeScript "deploy-dns" ''
          #!${stdenv.shell}
          d="${hostsDir}"
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
      dns = mkIf (hostsDir != null) {
        binary = writeScript "destroy-dns" ''
          #!${stdenv.shell}
          d="${hostsDir}"
          if [ -w "$d/${name}" ]; then
            truncate -s 0 -c "$d/${name}"
            rm -f "$d/${name}"
          fi
        '';
      };
    };
  };
}
