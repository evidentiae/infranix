{ config, lib, pkgs, ... }:

with lib;
with pkgs;

let

  cfg = config.services.nix-store-gcs-proxy;

  mkService = n: p: {
    wantedBy = [ "nix-daemon.service" ];
    before = [ "nix-daemon.service" ];
    serviceConfig.ExecStart = "${writeScriptBin "nix-store-gcs-proxy-${n}" ''
      #!${stdenv.shell}
      ${nix-store-gcs-proxy}/bin/nix-store-gcs-proxy \
        --bucket-name "${p.bucket}" \
        --addr "${p.listenHost}:${toString p.listenPort}"
    ''}/bin/nix-store-gcs-proxy-${n}";
  };

in {
  options = {
    services.nix-store-gcs-proxy.proxies = mkOption {
      default = {};
      type = with types; attrsOf (submodule ({...}: {
        options = {
          bucket = mkOption {
            type = types.str;
          };
          listenHost = mkOption {
            type = types.str;
            default = "127.0.0.1";
          };
          listenPort = mkOption {
            type = types.int;
            default = 3000;
          };
          publicKeys = mkOption {
            type = with types; listOf str;
            default = [];
          };
        };
      }));
    };
  };

  config = lib.mkIf (cfg.proxies != {}) {
    systemd.services = mapAttrs' (n: p:
      nameValuePair "nix-store-gcs-proxy-${n}" (mkService n p)
    ) cfg.proxies;
    nix.binaryCaches = map (p: "http://127.0.0.1:${toString p.listenPort}") (
      attrValues cfg.proxies
    );
    nix.binaryCachePublicKeys = unique (concatMap (p: p.publicKeys) (
      attrValues cfg.proxies
    ));
  };
}
