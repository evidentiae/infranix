{ config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

with (import ../lib/ipv4.nix);

let

  inherit (config) name;
  inherit (config.nixosHosts) hosts networking;
  inherit (splitCIDR networking.network) network prefix;

  firstHost = head (mapAttrsToList (n: _: n) hosts);

  initBinary = writeScript "init" ''
    #!${stdenv.shell}
    ${iproute2}/bin/ip addr add $IP/$PREFIX dev host0 && \
      ${iproute2}/bin/ip link set dev host0 up
    exec "$@"
  '';

  launchHost = host: writeScript "launch-host" ''
    #!${stdenv.shell}

    set -eu
    set -o pipefail

    host="$NOMAD_TASK_NAME"
    root="$NOMAD_TASK_DIR/root"
    alloc="$NOMAD_ALLOC_INDEX''${NOMAD_ALLOC_ID:0:8}"
    network_zone="$alloc"
    machine_id="$host-$alloc"

    mkdir "$root"

    bindmount_args=()
    IFS=',' read -r -a bindmounts <<< "$EXTRA_BIND_MOUNTS"
    for bm in "''${bindmounts[@]}"; do
      IFS=':' read -r h g <<< "$bm"
      if [ -n "$h" ] && [ -n "$g" ]; then
        bindmount_args+=("--bind-ro=$h:$g")
      fi
    done

    ${pkgs.systemd}/bin/systemd-nspawn \
      --setenv=IP="$IP" \
      --setenv=PREFIX="$PREFIX" \
      --rlimit=RLIMIT_NOFILE=infinity \
      --directory="$root" \
      --machine="$machine_id" \
      -U \
      "''${bindmount_args[@]}" \
      ${concatStringsSep " " (mapAttrsToList (h: g:
        ''--bind-ro="${h}:${g}"''
      ) host.readOnlyBindMounts)} \
      ${concatStringsSep " " (mapAttrsToList (h: g:
        ''--bind="${h}:${g}"''
      ) host.readWriteBindMounts)} \
      --tmpfs=/nix/var \
      --tmpfs=/var \
      --network-zone="$network_zone" \
      --kill-signal=SIGRTMIN+3 \
      "${initBinary}" "${host.nixos.out.system}/init" &

    link="vz-$network_zone"
    ip="${minHostAddress network prefix}/${toString prefix}"

    if [ "$NOMAD_TASK_NAME" == "${firstHost}" ]; then
      while ! ${iproute2}/bin/ip link show "$link" &>/dev/null; do
        ${coreutils}/bin/sleep 0.2
      done

      ${iproute2}/bin/ip addr add "$ip" dev "$link"
      ${iproute2}/bin/ip link set dev "$link" up
    fi

    function shutdown() {
      local machine="$1"
      local link="$2"

      ${pkgs.systemd}/bin/machinectl stop "$machine"

      if [ "$NOMAD_TASK_NAME" == "${firstHost}" ]; then
        #${iproute2}/bin/ip link set dev "$link" down || true
        sleep 1
        while ${iproute2}/bin/ip link show "$link" &>/dev/null; do
          ${iproute2}/bin/ip link delete "$link" || true
          ${coreutils}/bin/sleep 0.5
        done
      fi
    }

    trap "shutdown $machine_id $link" SIGINT

    wait
  '';

  makeTask = hostName: host: ''
    task "${hostName}" {
      driver = "raw_exec"
      kill_signal = "SIGINT"
      kill_timeout = "30s"
      config {
        command = "${launchHost host}"
      }
      env {
        EXTRA_BIND_MOUNTS = "''${var.extra-bind-mounts}"
        ${concatStringsSep "\n" (
          mapAttrsToList (k: v: ''${k} = "${v}"'') host.environment
        )}
      }
    }
  '';


in {
  imports = [
    ./named.nix
    ./nixos-containers.nix
  ];

  options = {
    nixos-nomad = {
      jobDefinition = mkOption {
        type = types.package;
      };
    };

    nixosHosts.hosts = mkOption {
      type = with types; attrsOf (submodule ({name, ...}: {
        options = {
          readOnlyBindMounts = mkOption {
            type = with types; attrsOf str;
            default = {};
          };
          readWriteBindMounts = mkOption {
            type = with types; attrsOf str;
            default = {};
          };
        };
        config = {
          readOnlyBindMounts."/nix/store" = "/nix/store";
        };
      }));
    };
  };

  config = {
    nixos-nomad.jobDefinition = writeText "job.nomad" ''
      variable "extra-bind-mounts" {
        type = string
      }
      job "${name}" {
        type = "service"
        datacenters = ["dc1"]
        group "hosts" {
          count = 1
          ${concatStrings (mapAttrsToList makeTask hosts)}
        }
      }
    '';
  };
}
