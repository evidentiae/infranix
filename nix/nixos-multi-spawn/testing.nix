{ config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

let

  inherit (import ../../lib.nix) genByte;

  cfg = config.testing.nixos-multi-spawn;

  ipMap = mapAttrs (name: _:
    "10.42.${genByte name 0}.${genByte name 3}"
  ) config.resources.nixos.hosts;

in {
  imports = [
    ../testing.nix
    ./default.nix
    ../named.nix
  ];

  options = {
    resources.nixos.hosts = mkOption {
      type = with types; attrsOf (submodule ({name, ...}: {
        config = {
          addresses.external = [ name ];
          addresses.internal = [ name ];
          nixos.imports = singleton {
            networking.hostName = name;
          };
        };
      }));
    };

    testing.nixos-multi-spawn = {
      wrapperPath = mkOption {
        type = types.path;
        default = "/run/wrappers/bin/nixos-multi-spawn";
        description = ''
          The location of the nixos-multi-spawn suid wrapper. It must be
          executable by the Nix build users
        '';
      };
      tailFiles = mkOption {
        type = with types; listOf str;
        default = [
          "fs/driver/out/logs/script-main.stdout"
          "fs/driver/out/logs/script-main.stderr"
          "fs/driver/out/logs/script-validation.stdout"
          "fs/driver/out/logs/script-validation.stderr"
        ];
      };
    };
  };

  config = {
    nixos-multi-spawn = {
      inherit (cfg) tailFiles;
      initScript = ''echo "$out" > /__out'';
      machines = mapAttrs (name: host: {
        environment.IP = "${ipMap.${name}}/16";
        inheritEnvVars = [ "out" ];
      }) config.resources.nixos.hosts;
    };

    resources.nixos.commonNixosImports = singleton {
      networking.useDHCP = false;
      networking.extraHosts = concatStrings (mapAttrsToList (n: host: ''
        ${ipMap.${n}} ${toString (unique (
          host.addresses.internal ++ host.addresses.external
        ))}
      '') config.resources.nixos.hosts);
    };

    resources.nixos.hosts.driver.nixos.imports = singleton {
      systemd.services.test-script = {
        wantedBy = [ "multi-user.target" ];
        wants = [ "network.target" ];
        after = [ "network.target" ];
        path = singleton (
          buildEnv {
            name = "script-path";
            paths = config.testing.scriptPath;
            pathsToLink = [ "/bin" "/sbin" ];
          }
        );
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${writeScriptBin "test-script" ''
            #!${stdenv.shell}

            mkdir -p /out/logs
            cd /out

            trap '${systemd}/bin/systemctl poweroff --force --force' EXIT

            export out="$(cat /__out)"
            rm /__out

            (
              set -e
              set -o pipefail
              ${config.testing.testScript}
            ) >> logs/script-main.stdout 2>> logs/script-main.stderr
            main_status="$?"

            sync -f .

            (
              set -e
              set -o pipefail
              ${config.testing.validationScript}
            ) >> logs/script-validation.stdout 2>> logs/script-validation.stderr
            validation_status="$?"

            sync -f .

            if [[ "$validation_status" == "0" ]]; then
              echo "$main_status" > script.status
            else
              echo "$validation_status" > script.status
            fi
          ''}/bin/test-script";
        };
      };
    };

    testing.result = stdenv.mkDerivation {
      inherit (config) name;

      requiredSystemFeatures = [ "nspawn" ];

      phases = [ "buildPhase" ];

      inherit (config.testing) succeedOnFailure;

      buildPhase = ''
        build=fs/driver/out

        rm -rf fs logs
        ${cfg.wrapperPath} ${config.nixos-multi-spawn.configFile} || true

        if ! [ -a "$build/script.status" ]; then
          echo "Unknown result"
          touch "$build/failed"
        elif [ "$(cat "$build/script.status")" != 0 ]; then
          echo "Test script failed"
          touch "$build/failed"
        fi

        # Put build products in place
        mv $build $out
        mkdir -p $out/logs/nspawn
        cp -n logs/* $out/logs/nspawn/
        mkdir -p $out/nix-support

        rm -f $out/script.status
        if [[ -a $out/failed ]]; then
          rm $out/failed
          exit 1
        fi
      '';
    };
  };
}
