{ config, pkgs, lib, ... }:

with lib;
with pkgs;
with builtins;

let

  cfg = config.libvirt.test;

  backend =
    if match "^lxc\+?[^:]+://.*$" cfg.connectionURI != null then "lxc"
    else if match "^qemu\+?[^:]+://.*$" cfg.connectionURI != null then "qemu"
    else throw "Cannot derive libvirt backend type from URI ${cfg.connectionURI}";

  inherit (import ../../lib.nix) hexByteToInt mkMAC;

  genByte = s: n: toString (hexByteToInt (
    substring n 2 (mkMAC s)
  ));

  domainOpts = { name, config, lib, ... }: {
    imports = [
      ./domain.nix
      cfg.defaultInstanceConfig
    ];

    options = {
      ip = mkOption {
        type = types.str;
        default = "10.@subnet@.${genByte name 0}.${genByte name 3}";
      };

      mac = mkOption {
        type = types.str;
        default = mkMAC name;
      };

      extraHostNames = mkOption {
        type = with types; listOf str;
        default = [];
      };
    };

    config = {
      _module.args = { inherit pkgs; };

      libvirt.domain = {
        inherit backend;
        lxc = mkIf (backend == "lxc") {
          mappedUid = "@uid@";
          mappedGid = "@gid@";
          rootPath = "/@mnt@/root-${name}";
        };
        name = "dom-@testid@-${name}";
        uuid = null;
        netdevs.eth0 = {
          mac = config.mac;
          network = "net-@testid@";
        };
        consoleFile = "@build@/log/${name}-console.log";
        fileShares.out = {
          guestPath = "/out";
          hostPath = "/@build@";
          readOnly = false;
        };
        fileShares.run = mkIf (backend == "lxc") {
          guestPath = "/run";
          hostPath = "/@mnt@/run-${name}";
          readOnly = false;
          neededForBoot = true;
        };
      };

      nixos.imports = singleton {
        services.nscd.enable = backend != "lxc";
        users.extraUsers.root.password = "root";
        services.journald.extraConfig = ''
          Storage=volatile
          ForwardToConsole=yes
          TTYPath=/dev/journaltty
          RateLimitBurst=0
        '';
        systemd.services.journaltty = {
          wantedBy = [ "systemd-journald.service" ];
          before = [ "systemd-journald.service" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            WorkingDirectory = "/out";
            ExecStart = "${pkgs.socat}/bin/socat -u PTY,link=/dev/journaltty CREATE:log/${name}-journal.log";
          };
        };
        networking = {
          hostName = name;
          firewall.enable = false;
        };
      };
    };
  };

  domNames = attrNames cfg.domains;
  domList = concatMapStringsSep "," (n: ''"${n}"'') domNames;

  padName = n:
    if any (n': stringLength n' > stringLength n) (attrNames cfg.tailFiles)
    then padName "${n} " else n;

  virshCreateCmds = concatStringsSep ";" (flatten [
    "net-create $build/libvirt/net-test.xml"
    (map (name: "create $build/libvirt/dom-${name}.xml") domNames)
  ]);

  virshDestroyCmds = concatStringsSep ";" (flatten [
    (map (name:
      "destroy dom-$testid-${name}"
    ) (filter (n: n != cfg.test-driver.hostName) domNames))
    "destroy dom-$testid"
    "net-destroy net-$testid"
  ]);

  # A temporary, isolated network for our test machines
  libvirtNetwork = writeText "network.xml" ''
    <network>
      <name>net-@testid@</name>
      <bridge name="virbr-@testid@" stp="off"/>
      <domain name="${cfg.network.domain}" localOnly="yes"/>
      <ip address="10.@subnet@.0.1" netmask="255.255.0.0">
        <dhcp>
          <range start="10.@subnet@.0.2" end="10.@subnet@.255.254" />
          ${concatStrings (mapAttrsToList (name: d: ''
            <host mac="${d.mac}" name="${name}" ip="${d.ip}"/>
          '') cfg.domains)}
        </dhcp>
      </ip>
      <dns>
        ${concatStrings (mapAttrsToList (name: d:
          optionalString (d.extraHostNames != []) ''
            <host ip="${d.ip}">
              ${concatMapStrings (n: ''
                <hostname>${removeSuffix "." n}</hostname>
              '') d.extraHostNames}
            </host>
          ''
        ) cfg.domains)}
      </dns>
    </network>
  '';

in {

  options = {

    libvirt.test = {

      name = mkOption {
        type = types.str;
        default = "libvirt-test";
      };

      succeedOnFailure = mkOption {
        type = types.bool;
        default = true;
      };

      network.domain = mkOption {
        type = types.str;
        default = "example.com";
      };

      retryCount = mkOption {
        type = types.int;
        default = 3;
      };

      retryOnTimeout = mkOption {
        type = types.bool;
        default = true;
      };

      timeouts = {
        sleepBetweenRetries = mkOption {
          type = types.int;
          default = 15;
        };
        singleTryTimeout = mkOption {
          type = types.int;
          default = 10*60;
        };
        totalTimeout = mkOption {
          type = types.int;
          default = 35*60;
        };
      };

      out = mkOption {
        type = types.path;
        description = ''
          The result of the test, as a nix derivation.
        '';
      };

      backend = mkOption {
        type = types.enum [ "qemu" "lxc" ];
        default = "qemu";
      };

      connectionURI = mkOption {
        type = types.str;
        default =
          if backend == "qemu" then "qemu:///system"
          else "lxc:///";
      };

      defaultInstanceConfig = mkOption {
        type = types.attrs;
        default = {};
      };

      domains = mkOption {
        default = {};
        type = with types; attrsOf (submodule domainOpts);
      };

      extraBuildSteps = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Extra build steps that is run as the last part of the build phase
          for the <code>output</code> build.
        '';
      };

      tailFiles = mkOption {
        type = with types; attrsOf (listOf str);
        default = {
          OUT = [ "log/stdout" ];
          ERR = [ "log/stderr" ];
        } // genAttrs domNames (n: [ "log/${n}-console.log" ])
          // genAttrs domNames (n: [ "log/${n}-journal.log" ]);
      };

      test-driver = {
        hostName = mkOption {
          type = types.str;
          default = "driver";
        };

        script = mkOption {
          type = types.path;
          description = ''
            The main test script. This is run from a separate libvirt machine
            (the test driver machine) that is part of the same network as the
            other libvirt machines (defined by the <code>domains</code>
            option).
          '';
        };

        scriptPath = mkOption {
          type = with types; listOf path;
          default = [];
        };

        extraModules = mkOption {
          default = [];
          type = with types; listOf unspecified;
          description = ''
            Extra NixOS modules that should be added to the test driver
            machine.
          '';
        };
      };

    };

  };

  config = {

    libvirt.test.domains.${cfg.test-driver.hostName} = {
      libvirt.domain.name = mkForce "dom-@testid@";
      nixos.imports = cfg.test-driver.extraModules ++ [{
        systemd.services.test-script = {
          wantedBy = [ "multi-user.target" ];
          wants = [ "network.target" ];
          after = [ "network.target" ];
          path = singleton (
            buildEnv {
              name = "script-path";
              paths = cfg.test-driver.scriptPath;
              pathsToLink = [ "/bin" "/sbin" ];
            }
          );
          serviceConfig = {
            WorkingDirectory = "/out";
            Type = "oneshot";
            ExecStart = "${pkgs.writeScriptBin "test-script" ''
              #!${bash}/bin/bash
              "${cfg.test-driver.script}" >> log/stdout 2>> log/stderr
              echo "$?" > script.status
              sync -f .
              ${pkgs.systemd}/bin/systemctl poweroff --force --force
            ''}/bin/test-script";
          };
        };
      }];
    };

    libvirt.test.out = pkgs.stdenv.mkDerivation {
      inherit (cfg) name;

      requiredSystemFeatures = [ "libvirt" ];

      src = runCommand "test-src"
        { preferLocalBuild = true;
          allowSubstitutes = false;
        } ''
          mkdir $out
          ${concatStrings (mapAttrsToList (n: d: ''
            ln -sv "${d.libvirt.domain.xmlFile}" "$out/dom-${n}.xml"
          '') cfg.domains)}
          ln -s "${libvirtNetwork}" "$out/net-test.xml"
        '';

      phases = [ "buildPhase" ];

      buildInputs = singleton (
        writeScriptBin "extra-build-steps" ''
          #!${bash}/bin/bash
          set -e
          ${cfg.extraBuildSteps}
        ''
      );

      inherit (cfg) succeedOnFailure;

      buildPhase = ''
        function prettytail() {
          local header="$1"
          local file="$2"
          tail --pid $virshpid -f "$file" | while read l; do
            printf "%s%s\n" "$header" "$l"
          done
        }

        function now() {
          date +%s
        }

        function log() {
          printf "%05d %s\n" $(($(now) - $starttime)) "$1"
        }

        function err() {
          log "error: $1"
        }

        function run_one_build() {
          testid="$(${pkgs.utillinux}/bin/uuidgen -r)"
          testid="''${testid%%-*}"
          export testid="''${testid:0:7}"
          export subnet="$(($RANDOM % 255))"
          export build="$(readlink -m "$(mktemp -dp "$pwd")")"
          export mnt="$(readlink -m "$(mktemp -dp "$pwd")")"

          # Setup directories and libvirt XML files
          mkdir -p $build/{log,libvirt} $build/hosts/{${domList}}
          touch $build/log/std{out,err} $build/log/{${domList}}-console.log
          cp -t $build/libvirt "$src"/*
          for f in $build/libvirt/{dom,net}-*.xml; do substituteAllInPlace "$f"; done
          ${optionalString (backend == "lxc") ''mkdir $mnt/{root,run}-{${domList}} ''}

          # Let libvirt access paths inside the build directory and write to out dirs
          chmod a+x .
          chmod a+w -R $build

          log "Starting libvirt machines"
          ${pkgs.libvirt}/bin/virsh -c "${cfg.connectionURI}" \
            "${virshDestroyCmds}" &>/dev/null || true
          ${pkgs.libvirt}/bin/virsh -c "${cfg.connectionURI}" \
            "${virshCreateCmds}" >/dev/null || return
          ${pkgs.libvirt}/bin/virsh -c "${cfg.connectionURI}" \
            "event dom-$testid lifecycle --timeout ${toString cfg.timeouts.singleTryTimeout}" >/dev/null &
          export virshpid=$!

          ${concatStrings (flatten (mapAttrsToList (n: fs: map (f: ''
            prettytail "${padName n}" "$build/${f}" &
          '') fs) cfg.tailFiles))}

          wait $virshpid || true
        }

        uid="$(id -u)"
        gid="$(id -g)"
        pwd="$(pwd)"
        starttime="$(now)"
        retries_left="${toString cfg.retryCount}"

        while true; do
          try_starttime="$(now)"
          run_one_build || true
          log "Destroying libvirt machines"
          ${pkgs.libvirt}/bin/virsh -c "${cfg.connectionURI}" \
            "${virshDestroyCmds}" &>/dev/null || true

          try_time="$(($(now) - $try_starttime))"
          total_time="$(($(now) - $starttime))"
          retries_left="$(($retries_left - 1))"

          if (($total_time > ${toString cfg.timeouts.totalTimeout})); then
            err "Total build timeout passed"
            touch "$build/failed"
            break
          elif (($try_time > ${toString cfg.timeouts.singleTryTimeout})); then
            if ((retries_left <= 0)) && [ -z "${toString cfg.retryOnTimeout}"]; then
              err "Timeout, not retrying"
              touch "$build/failed"
              break
            fi
          elif ! [ -a "$build/script.status" ]; then
            if ((retries_left <= 0)); then
              err "Unknown result, no retries left"
              touch "$build/failed"
              break
            fi
          else
            case "$(cat "$build/script.status")" in
              0)
                break
                ;;
              2)
                if ((retries_left <= 0)); then
                  err "Retries exhausted"
                  touch "$build/failed"
                  break
                fi
                ;;
              *)
                err "Test script failed"
                touch "$build/failed"
                break
                ;;
            esac
          fi

          log "Retrying build in ${toString cfg.timeouts.sleepBetweenRetries} seconds"
          sleep ${toString cfg.timeouts.sleepBetweenRetries}
        done

        # Put build products in place
        cp -rnT $build $out
        mkdir -p $out/nix-support

        (
          echo "file log $out/log/stdout"
          echo "file log $out/log/stderr"
          for i in ${toString domNames}; do for l in console journal; do
            echo "file log $out/log/$i-$l.log"
          done; done
        ) >> $out/nix-support/hydra-build-products

        out=$out extra-build-steps || touch $out/failed

        rm -f $out/script-status
        if [[ -a $out/failed ]]; then
          rm $out/failed
          exit 1
        fi
      '';
    };

  };

}
