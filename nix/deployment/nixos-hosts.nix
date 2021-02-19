{ config, lib, pkgs, ... }:

with lib;
with pkgs;

let

  inherit (config.nixosHosts) hosts;

  activationScript = name: host: writeScript "activate-${name}" ''
    #!${stdenv.shell}
    set -e
    set -o pipefail

    reboot=""
    action=""

    server_info=${config.cli.commands.server.subCommands.info.binary}

    for arg in "$@"; do
      for a in reboot boot dry-run; do
        if [ "$arg" == "--$a" ]; then
          if [ -n "$action" ]; then
            echo >&2 "You can specify at most one deploy action"
            exit 1
          else
            action="$a"
          fi
        fi
      done
      if [ -z "$action" ]; then
        echo >&2 "Unknown deploy action '$arg'"
        exit 1
      fi
    done

    ssh_address="$($server_info "${name}" ssh_address)"
    ssh_args="$($server_info "${name}" ssh_args)"
    nixstore_ssh_address="$($server_info "${name}" nixstore_ssh_address)"
    sys="${host.nixos.out.system}"
    ssh="ssh -lroot $ssh_args $ssh_address"
    setsys="yes"

    if [[ "$nixstore_ssh_address" != "$ssh_address" ]]; then
      setsys=""
    fi

    if [ -z "$action" ]; then
      action=switch
    elif [ "$action" == "dry-run" ]; then
      action=dry-activate
      setsys=""
    elif [ "$action" == "reboot" ]; then
      reboot=1
      action=boot
    fi

    $ssh "${concatStringsSep "&&" [
      "shopt -s huponexit"
      "(test -z $setsys || nix-env -p /nix/var/nix/profiles/system --set $sys)"
      "$sys/bin/switch-to-configuration $action"
    ]}" 2>&1 | while read line; do
      echo >&2 "[${name}] $line"
    done

    if [ -n "$reboot" ]; then
      echo "Rebooting ${name}..."
      ($ssh "shopt -s huponexit && systemctl reboot") || true
      sleep 5
      end=$((SECONDS+60))
      while [ $SECONDS -lt $end ] && ! $ssh true; do
        sleep 5
      done
      echo "Rebooted ${name}"
    fi
  '';

in {

  imports = [
    ../nixos-hosts.nix
    ../cli.nix
  ];

  cli.commands = mkIf (hosts != {}) {

    activate.steps = (mapAttrs (name: host: {
      dependencies = ["install"];
      binary = activationScript name host;
    }) hosts) // {
      install.binary = writeScript "install" ''
        #!${stdenv.shell}
        exec ${config.cli.commands.install.package}/bin/install "$@"
      '';
    };

    install = {
      steps = mapAttrs (name: host: {
        binary = with host.nixos.store.ssh; writeScript "install-${name}" ''
          #!${stdenv.shell}
          set -e

          server_info=${config.cli.commands.server.subCommands.info.binary}
          nixstore_ssh_address="$($server_info "${name}" nixstore_ssh_address)"
          nixstore_ssh_args="$($server_info "${name}" nixstore_ssh_args)"
          ssh_address="$($server_info "${name}" ssh_address)"
          ssh_args="$($server_info "${name}" ssh_args)"
          ssh="ssh -lroot $ssh_args $ssh_address"
          sys="${host.nixos.out.system}"

          if [[ "$nixstore_ssh_address" != localhost ]]; then
            $ssh "${concatStringsSep "&&" [
              "shopt -s huponexit"
              "ln -sfT $sys /nix/var/nix/gcroots/next-system"
            ]}" 2>&1 | while read line; do
              echo >&2 "[${name}] $line"
            done

            NIX_SSHOPTS="-lroot $nixstore_ssh_args" \
              nix copy -s --to "ssh://$nixstore_ssh_address" "$sys"
          fi
        '';
      }) hosts;
    };

    deploy.completions = singleton (
      "deploy (--reboot|--boot|--dry-run)"
    );

    # We don't add a dependency to 'install' here, since that dependency
    # already is defined in the 'activate' command above. We should probably
    # spend some time on making our command runner and Nix options saner...
    deploy.steps = {
      activate.binary = writeScript "activate" ''
        #!${stdenv.shell}
        exec ${config.cli.commands.activate.package}/bin/activate "$@"
      '';
      post-activate = {
        binary = "${coreutils}/bin/true";
        dependencies = [ "activate" ];
      };
    };

  };

}
