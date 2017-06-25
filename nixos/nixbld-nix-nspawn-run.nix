# WARNING! This sets up nixos-multi-spawn as a suid program. Theoretically
# it should be fine, since nixos-multi-spawn only runs unprivileged containers,
# and gives no possibility to configure the systemd-nspawn options.

{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.nixos-multi-spawn;

in {
  options = {

    programs.nixos-multi-spawn = {
      package = mkOption {
        type = types.package;
        default = import (pkgs.fetchFromGitHub {
          owner = "evidentiae";
          repo = "nixos-multi-spawn";
          rev = "b6ae1df2293628f7ee7e3d07a3b06ef1189b7b23";
          sha256 ="1q1913i480468scsc58fpxgc1bv31wwmdwszfv5nsrvh8dmvzc4w";
        }) { inherit pkgs; };
      };
    };

  };

  config = {

    # TODO Maybe we should support multiple wrappers with different groups,
    # but for now it is enough if it works in nix builds
    security.wrappers.nixos-multi-spawn = {
      source = "${cfg.package}/bin/nixos-multi-spawn";
      owner = "root";
      group = "nixbld";
      permissions = "u+rsx,g+x";
    };

    # Each container takes at least 4 inotify file handles, so you quickly reach
    # limit 128 when spawning many containers
    boot.kernel.sysctl."fs.inotify.max_user_instances" = 2048;

    # systemd-nspawn doesn't automatically UP the bridge so we do it with udev
    # Probably nicer to do with networkd, but we're not using that yet
    services.udev.extraRules = concatStringsSep ", " [
      ''KERNEL=="vz-*"''
      ''SUBSYSTEM=="net"''
      ''ATTR{operstate}=="down"''
      ''RUN+="${pkgs.iproute}/bin/ip link set dev %k up"''
    ];

    networking.dhcpcd.denyInterfaces = [ "vb-*" ];

    # Set a gap of 65536 between all nixbld uids. This allows us to map the
    # root user of each container to the corresponding nixbld user, which in
    # turn helps when nix kills build processes
    users.users = listToAttrs (map (n:
      nameValuePair "nixbld${toString n}" {
        uid = mkForce (3*65536 + (65536 * (n - 1)));
      }
    ) (range 1 config.nix.nrBuildUsers));

    systemd.services.empty-bridge-cleaner = {
      wantedBy = [ "multi-user.target" ];
      startAt = "*-*-* *:30:00";
      path = with pkgs; [ iproute findutils ];
      script = ''
        links="$(bridge link show)"

        for b in $(ip -o link show type bridge | cut -d : -f2 | tr -d ' ' | egrep '^vz-'); do
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
  };
}
