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
          echo "''${line/CONFIG=/}" >> nixos-multi-spawn0.json
          if ${pkgs.jq}/bin/jq -e '.zone' nixos-multi-spawn0.json >/dev/null; then
            zone=$(${pkgs.jq}/bin/jq -r '.zone' nixos-multi-spawn0.json)
            cp nixos-multi-spawn0.json nixos-multi-spawn.json
          else
            zone=$(od -vAn -N4 -tu4 < /dev/urandom | tr -d ' ')
            ${pkgs.jq}/bin/jq ". + {\"zone\": \"$zone\"}" \
              nixos-multi-spawn0.json > nixos-multi-spawn.json
          fi
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
      prefix="''${net#*/}"
      ip="$(${pkgs.ipcalc}/bin/ipcalc "$net" | \
        ${pkgs.gnugrep}/bin/grep HostMin | ${pkgs.gawk}/bin/awk '{print $2}')/$prefix"
      iproute=${pkgs.iproute}/bin/ip
      link="vz-$zone"
      while ! $iproute link show "$link" &>/dev/null; do
        ${pkgs.coreutils}/bin/sleep 0.1
      done
      $iproute addr add "$ip" dev "$link"
      $iproute link set dev "$link" up
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

in {

  options = {
    services.nixos-multi-spawn = {
      enable = mkOption {
        type = types.bool;
        default = false;
      };

      package = mkOption {
        type = types.package;
        default = pkgs.nixos-multi-spawn;
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

    environment.systemPackages = [ pkgs.nixos-multi-spawn-client ];

    nix.sandboxPaths = mkIf cfg.allowNix [
      "/run/nixos-multi-spawn/nixbld.socket"
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
            LimitNOFILE = "200000";
            PrivateTmp = true;
            KillMode = "process";
            Type = "notify";
            NotifyAccess = "all";
            ExecStart = "${pkgs.socat}/bin/socat FD:3 EXEC:${server},nofork";
            TimeoutStopSec = 300;
          };
        };
      }) cfg.allowedGroups)
    );

    # Each container takes at least 4 inotify file handles, so you quickly reach
    # limit 128 when spawning many containers
    boot.kernel.sysctl."fs.inotify.max_user_instances" = 2048;
    boot.kernel.sysctl."vm.max_map_count" = 262144;

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
