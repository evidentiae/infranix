{ config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

with (import ../lib/ipv4.nix);

let

  inherit (config) name;
  inherit (config.nixosHosts) hosts networking;
  inherit (splitCIDR networking.network) network prefix;

  initBinary = writeScript "init" ''
    #!${stdenv.shell}
    ${iproute}/bin/ip addr add $IP/$PREFIX dev host0 && \
      ${iproute}/bin/ip link set dev host0 up
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

    exec ${pkgs.systemd}/bin/systemd-nspawn \
      --setenv=IP="$IP" \
      --setenv=PREFIX="$PREFIX" \
      --rlimit=RLIMIT_NOFILE=infinity \
      --directory="$root" \
      --machine="$machine_id" \
      -U \
      ''${GIT_REPO:+--bind-ro="$GIT_REPO:/git-repo"} \
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
      "${initBinary}" "${host.nixos.out.system}/init"
  '';

  setupNetwork = writeScript "setup-network" ''
    #!${stdenv.shell}

    set -eu
    set -o pipefail

    iproute=${iproute}/bin/ip
    alloc="$NOMAD_ALLOC_INDEX''${NOMAD_ALLOC_ID:0:8}"
    network_zone="$alloc"
    link="vz-$network_zone"
    ip="${minHostAddress network prefix}/${toString prefix}"

    while ! $iproute link show "$link" &>/dev/null; do
      ${coreutils}/bin/sleep 0.1
    done

    $iproute addr add "$ip" dev "$link"
    $iproute link set dev "$link" up

    exec ${coreutils}/bin/sleep infinity
  '';

  makeTask = hostName: host: ''
    task "${hostName}" {
      driver = "raw_exec"
      kill_signal = "SIGTERM"
      config {
        command = "${launchHost host}"
      }
      env {
        GIT_REPO = "''${var.git-repo}"
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
      variable "git-repo" {
        type = string
      }
      job "${name}" {
        type = "service"
        datacenters = ["dc1"]
        group "hosts" {
          count = 1
          task "setup-network" {
            driver = "raw_exec"
            config {
              command = "${setupNetwork}"
            }
          }
          ${concatStrings (mapAttrsToList makeTask hosts)}
        }
      }
    '';
  };
}
