{ config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

let

  cfg = config.testing.nixos-multi-spawn;

  logMsg =
    if config.testing.succeedOnFailure then
      "Logs can be found in: $out/logs"
    else
      "";

in {
  imports = [
    ../named.nix
    ../nixos-multi-spawn.nix
    ../testing.nix
  ];

  config = {
    nixos-multi-spawn = {
      tailFiles = [
        "fs/driver/out/logs/script-main.stdout"
        "fs/driver/out/logs/script-main.stderr"
        "fs/driver/out/logs/script-validation.stdout"
        "fs/driver/out/logs/script-validation.stderr"
      ];
    };

    nixosHosts.networking.network = "10.42.0.0/16";

    nixosHosts.hosts.driver.nixos.imports = singleton {
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

      buildInputs = [
        nixos-multi-spawn-client
        gnused
      ];

      inherit (config.testing) succeedOnFailure;

      buildPhase = ''
        nixos-multi-spawn-client \
          ${config.nixos-multi-spawn.configFile} \
          ${config.nixosHosts.networking.network} \
          || true

        result=fs/driver/out
        if ! [ -d "$result" ] || [ -z "$(ls -A "$result")" ]; then
          echo >&2 "No results produced, aborting build"
          mkdir -p "$result/nix-support"
          touch "$result/nix-support/aborted"
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
        if [ -d logs ]; then
          cp -nrT logs $out/logs/nspawn
        fi

        if [ -a "$out/nix-support/hydra-build-products" ]; then
          sed -i "s,@out@,$out,g" "$out/nix-support/hydra-build-products"
        fi

        if [ -a failed ]; then
          echo >&2 "Build failed. ${logMsg}"
          exit 1
        fi
      '';
    };
  };
}
