{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.nixos-multi-spawn;

  netRegex = "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$";

  server = pkgs.writeScript "nixos-multi-spawn-server" ''
    #!${pkgs.stdenv.shell}

    mkdir -p /tmp/out
    cd /tmp/out

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

    # Read arguments send through the socket by the client
    while read line; do
      case "$line" in
        NET=*)
          net=''${line/NET=/}
          ;;
        CONFIG=*)
          echo "''${line/CONFIG=/}" >> nixos-multi-spawn.json
          ${cfg.package}/bin/nixos-multi-spawn nixos-multi-spawn.json 2>&1 &
          nms_pid=$!
          break
          ;;
        *) ;;
      esac
    done

    if [ -z "$nms_pid" ]; then
      echo >&2 "error: No nixos-multi-spawn configuration provided"
      exit 1
    fi

    wait_for_eof <&1 &
    eof_pid=$!

    if [[ "$net" =~ ${netRegex} ]]; then
      netid="$(${pkgs.jq}/bin/jq -r .netid nixos-multi-spawn.json)"
      if [ -n "$netid" ] && [ "$netid" != null ]; then
        prefix="''${net#*/}"
        ip="$(${pkgs.ipcalc}/bin/ipcalc -nb "$net" | \
          ${pkgs.gnugrep}/bin/grep HostMin | ${pkgs.gawk}/bin/awk '{print $2}')/$prefix"
        iproute=${pkgs.iproute}/bin/ip
        link="vz-$netid"
        while ! $iproute link show "$link" &>/dev/null; do
          ${pkgs.coreutils}/bin/sleep 0.1
        done
        $iproute addr add "$ip" dev "$link"
        $iproute link set dev "$link" up
      fi
    fi

    wait -n "$nms_pid" "$eof_pid" || true
    shutdown

    if [ -a eof ]; then
      echo >&2 "Peer disconnected, exiting"
    else
      echo DONE
      cd /tmp
      ${pkgs.gnutar}/bin/tar -c -f - --remove-files -C out .
    fi
  '';

  client = pkgs.writeScriptBin "nixos-multi-spawn-client" ''
    #!${pkgs.stdenv.shell}
    set -e
    set -o pipefail

    config="$1"
    net="$2"
    socat=${pkgs.socat}/bin/socat
    socket="/run/nixos-multi-spawn/$(id -gn).socket"

    if ! [ -w "$socket" ]; then
      echo >&2 "Socket '$socket' not writable"
      exit 1
    fi

    if ! [ -r "$config" ]; then
      echo >&2 "Config '$config' not readable"
      exit 1
    fi

    if [ -z "$net" ] || ! [[ "$net" =~ ${netRegex} ]]; then
      echo >&2 "Invalid net '$net'"
      exit 1
    fi

    function printargs() {
      echo -e "\n$1"
      test -n "$net" && echo -e "\nNET=$net"
      echo "CONFIG=$(${pkgs.jq}/bin/jq -cr . "$config")"
    }

    function notify_ready() {
      if [ -n "$NOTIFY_SOCKET" ]; then
        echo "READY=1" | $socat UNIX-SENDTO:$NOTIFY_SOCKET STDIO
      fi
    }

    printargs | $socat -,ignoreeof UNIX-CONNECT:"$socket" | (
      notify_ready
      while read line; do
        if [ "$line" == "DONE" ]; then
          ${pkgs.gnutar}/bin/tar xBf -
        else
          echo "$line"
        fi
      done
    )
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
        "nixos-multi-spawn-${group}@" = {
          reloadIfChanged = false;
          restartIfChanged = false;
          serviceConfig = {
            PrivateTmp = true;
            KillMode = "process";
            Type = "notify";
            NotifyAccess = "all";
            ExecStart = "${pkgs.socat}/bin/socat FD:3 EXEC:${server},nofork";
          };
        };
      }) cfg.allowedGroups)
    );

    # Each container takes at least 4 inotify file handles, so you quickly reach
    # limit 128 when spawning many containers
    boot.kernel.sysctl."fs.inotify.max_user_instances" = 2048;

    networking = {
      dhcpcd.denyInterfaces = [
        "vb-*"
        "vz-*"
      ];
      networkmanager.unmanaged = [
        "interface-name:vb-*"
        "interface-name:vz-*"
      ];
    };
  };
}
