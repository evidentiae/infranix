{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.nixos-multi-spawn;

  setupLink = pkgs.writeScript "link-up" ''
    #!${pkgs.stdenv.shell}

    link="$1"

    case "$link" in
      vz-10*)
        ${pkgs.iproute}/bin/ip addr add 10.''${link##vz-10}.0.1/16 dev "$link"
        ;;
      vz-172*)
        ${pkgs.iproute}/bin/ip addr add 10.''${link##vz-172}.0.1/16 dev "$link"
        ;;
      *)
        ;;
    esac

    ${pkgs.iproute}/bin/ip link set dev "$link" up
  '';

  server = pkgs.writeScript "nixos-multi-spawn-server" ''
    #!${pkgs.stdenv.shell}

    cd /tmp

    shutdown() {
      kill -TERM "$nms_pid" 2>/dev/null || true
      kill -TERM "$eof_pid" 2>/dev/null || true
      wait "$eof_pid" "$nms_pid" || true
    }

    wait_for_eof() {
      while read -s -n 1 dummy; do true; done
      touch eof
    }

    trap shutdown TERM INT

    while read line; do
      case "$line" in
      START)
        ${cfg.package}/bin/nixos-multi-spawn nixos-multi-spawn.json 2>&1 &
        nms_pid=$!
        break
        ;;
      *)
        echo "$line" >> nixos-multi-spawn.json
        ;;
      esac
    done

    wait_for_eof <&1 &
    eof_pid=$!

    wait -n "$nms_pid" "$eof_pid" || true
    shutdown

    if [ -a eof ]; then
      echo >&2 "Peer disconnected, exiting"
    else
      echo DONE
      ${pkgs.gnutar}/bin/tar -c -f - --remove-files .
    fi
  '';

  client = pkgs.writeScriptBin "nixos-multi-spawn-client" ''
    #!${pkgs.stdenv.shell}

    set -e

    config="$1"
    socket="/run/nixos-multi-spawn/$(id -gn).socket"

    if ! [ -w "$socket" ]; then
      echo >&2 "Socket '$socket' not writable"
      exit 1
    fi

    if ! [ -r "$config" ]; then
      echo >&2 "Config '$config' not readable"
      exit 1
    fi

    echo -e "\nSTART" | cat "$config" - | \
      ${pkgs.socat}/bin/socat -,ignoreeof UNIX-CONNECT:"$socket" | \
        while read line; do
          if [ "$line" == "DONE" ]; then
            ${pkgs.gnutar}/bin/tar xBf -
          else
            echo "$line"
          fi
        done || true
  '';

in {

  options = {
    services.nixos-multi-spawn = {
      enable = mkOption {
        type = types.bool;
        default = false;
      };

      package = mkOption {
        type = types.package;
        default = import (pkgs.fetchFromGitHub {
          owner = "evidentiae";
          repo = "nixos-multi-spawn";
          rev = "77ee14b56f900f03f52fca118e297bf0154d49fc";
          sha256 ="1ipj1yrkvssbq2k3vyvlw078gw2xvc6ifj854sfmkpnm319xgjvi";
        }) { inherit pkgs; };
      };

      allowedGroups = mkOption {
        type = with types; listOf str;
        default = [];
        apply = gs: unique (gs ++ optional cfg.allowNix "nixbld");
      };

      allowNix = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };

  config = mkIf cfg.enable {

    environment.systemPackages = [ client ];

    nix.sandboxPaths = mkIf cfg.allowNix [
      "/run/nixos-multi-spawn/nixbld.socket"
      "/run/current-system/sw/bin/nixos-multi-spawn-client"
    ];

    systemd.sockets = mkMerge (map (group: {
      "nixos-multi-spawn-${group}" = {
        wantedBy = [ "sockets.target" ];
        listenStreams = [ "/run/nixos-multi-spawn/${group}.socket" ];
        socketConfig = {
          Accept = true;
          SocketMode = "0660";
          SocketUser = "root";
          SocketGroup = group;
        };
      };
    }) cfg.allowedGroups);

    systemd.services = mkMerge (
      (map (group: {
        "nixos-multi-spawn-${group}@".serviceConfig = {
          PrivateTmp = true;
          KillMode = "process";
          ExecStart = "${pkgs.socat}/bin/socat FD:3 EXEC:${server},nofork";
        };
      }) cfg.allowedGroups) ++
      singleton {
        empty-bridge-cleaner = {
          wantedBy = [ "multi-user.target" ];
          startAt = "*-*-* *:30:00";
          path = with pkgs; [ iproute findutils ];
          script = ''
            links="$(bridge link show)"

            for b in $(ip -o link show type bridge | cut -d : -f2 | \
              tr -d ' ' | egrep '^vz-')
            do
              if ! (echo "$links" | grep -q " master $b "); then
                echo "Deleting empty bridge $b"
                ip link del "$b" || true
              fi
            done
          '';
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = "false";
            Restart = "no";
          };
        };
      }
    );

    # Each container takes at least 4 inotify file handles, so you quickly reach
    # limit 128 when spawning many containers
    boot.kernel.sysctl."fs.inotify.max_user_instances" = 2048;

    # systemd-nspawn doesn't automatically up the bridge so we do it with udev
    # Probably nicer to do with networkd, but we're not using that yet
    services.udev.extraRules = concatStringsSep ", " [
      ''KERNEL=="vz-*"''
      ''SUBSYSTEM=="net"''
      ''ATTR{operstate}=="down"''
      ''RUN+="${setupLink} %k"''
    ];

    networking = {
      dhcpcd.denyInterfaces = [ "vb-*" ];
      networkmanager.unmanaged = [ "interface-name:vb-*" ];
    };
  };
}
