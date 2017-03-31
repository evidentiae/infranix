# WARNING! This sets up nix-systemd-nspawn as a suid program. Theoretically
# it should be fine, since nix-nspawn-run only runs unprivileged containers,
# and gives no possibility to configure the systemd-nspawn options.

{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.nix-nspawn-run;

in {
  options = {

    programs.nix-nspawn-run = {
      package = mkOption {
        type = types.package;
      };
    };

  };

  config = {

    # TODO Maybe we should support multiple wrappers with different groups,
    # but for now it is enough if it works in nix builds
    security.wrappers.systemd-nspawn-runner = {
      source = "${cfg.package}/bin/nix-nspawn-run";
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
