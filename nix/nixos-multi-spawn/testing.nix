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
      machines = mapAttrs (name: host: {
        environment.IP = "${ipMap.${name}}/16";
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

      requiredSystemFeatures = [ "nixos-multi-spawn" ];

      phases = [ "buildPhase" ];

      inherit (config.testing) succeedOnFailure;

      buildPhase = ''
        /run/current-system/sw/bin/nixos-multi-spawn-client \
          ${config.nixos-multi-spawn.configFile} 10.42.0.0/16 || true

        result=fs/driver/out
        if ! [ -d "$result" ] || [ -z "$(ls -A "$result")" ]; then
          echo >&2 "No results produced"
          mkdir -p "$result"
          touch "$result/this_dir_is_empty"
          touch failed
        elif ! [ -a "$result/script.status" ]; then
          echo >&2 "No script status found"
          touch failed
        elif [ "$(cat "$result/script.status")" != 0 ]; then
          rm "$result/script.status"
          echo >&2 "Test script failed"
          touch failed
        fi

        # Put build products in place
        mv $result $out
        mkdir -p $out/logs/nspawn
        cp -n logs/* $out/logs/nspawn/

        if [ -a "$out/nix-support/hydra-build-products" ]; then
          ${gnused}/bin/sed -i "s,@out@,$out,g" \
            "$out/nix-support/hydra-build-products"
        fi

        if [ -a failed ]; then
          echo >&2 "Build failed"
          exit 1
        fi
      '';
    };
  };
}
