{ config, pkgs, lib, ... }:

with lib;

let

  cfg = config.networking.networkmanager.mutableHosts;

  enable = config.networking.networkmanager.enable && cfg.enable &&
    cfg.hostsDirs != {};

in {
  options = {
    networking.networkmanager.mutableHosts = {
      enable = mkOption {
        type = types.bool;
        default = false;
      };
      hostsDirs = mkOption {
        type = with types; attrsOf (submodule {
          options = {
            user = mkOption {
              type = types.str;
              default = "root";
            };
            group = mkOption {
              type = types.str;
              default = "root";
            };
          };
        });
        default = {};
      };
    };
  };

  config = mkIf enable {

    networking.networkmanager.dns = "dnsmasq";

    systemd.services.nm-setup-hostsdirs = {
      wantedBy = [ "NetworkManager.service" ];
      before = [ "NetworkManager.service" ];
      script = concatStrings (mapAttrsToList (n: d: ''
        mkdir -p "/run/NetworkManager/hostsdirs/${n}"
        chown "${d.user}:${d.group}" "/run/NetworkManager/hostsdirs/${n}"
        chmod 0775 "/run/NetworkManager/hostsdirs/${n}"
      '') cfg.hostsDirs);
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    environment.etc = {
      "NetworkManager/dnsmasq.d/dyndns.conf".text = concatMapStrings (n: ''
        hostsdir=/run/NetworkManager/hostsdirs/${n}
      '') (attrNames cfg.hostsDirs);
    };

  };
}
