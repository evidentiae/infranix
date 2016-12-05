{ config, pkgs, lib, ... }:

with lib;
with pkgs;

let

  cfg = config.libvirt.test;

  inherit (import ../../lib.nix) hexByteToInt mkMAC;

  genByte = s: n: toString (hexByteToInt (
    substring n 2 (mkMAC s)
  ));

  instanceOpts = { name, config, lib, ... }: {
    imports = [
      ../libvirt.nix
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

      libvirt = {
        backend = cfg.backend;
        lxc = mkIf (cfg.backend == "lxc") {
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
        fileShares.run = mkIf (cfg.backend == "lxc") {
          guestPath = "/run";
          hostPath = "/@mnt@/run-${name}";
          readOnly = false;
          neededForBoot = true;
        };
      };

      nixos.modules = singleton {
        services.nscd.enable = cfg.backend != "lxc";
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

  instNames = attrNames cfg.instances;
  instList = concatMapStringsSep "," (n: ''"${n}"'') instNames;

  padName = n:
    if any (n': stringLength n' > stringLength n) (attrNames cfg.tailFiles)
    then padName "${n} " else n;

  virshCreateCmds = concatStringsSep ";" (flatten [
    "net-create $build/libvirt/net-test.xml"
    (map (name: "create $build/libvirt/dom-${name}.xml") instNames)
  ]);

  virshDestroyCmds = concatStringsSep ";" (flatten [
    (map (name:
      "destroy dom-$testid-${name}"
    ) (filter (n: n != cfg.test-driver.hostName) instNames))
    "destroy dom-$testid"
    "net-destroy net-$testid"
  ]);

  # A temporary, isolated network for our test machines
  libvirtNetwork = writeText "network.xml" ''
    <network>
      <name>net-@testid@</name>
      <bridge name="virbr-@testid@" stp="off"/>
      <domain name="${cfg.domain}" localOnly="yes"/>
      <ip address="10.@subnet@.0.1" netmask="255.255.0.0">
        <dhcp>
          <range start="10.@subnet@.0.2" end="10.@subnet@.255.254" />
          ${concatStrings (mapAttrsToList (name: i: ''
            <host mac="${i.mac}" name="${name}" ip="${i.ip}"/>
          '') cfg.instances)}
        </dhcp>
      </ip>
      <dns>
        ${concatStrings (mapAttrsToList (name: i:
          optionalString (i.extraHostNames != []) ''
            <host ip="${i.ip}">
              ${concatMapStrings (n: ''
                <hostname>${removeSuffix "." n}</hostname>
              '') i.extraHostNames}
            </host>
          ''
        ) cfg.instances)}
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

      domain = mkOption {
        type = types.str;
        default = "example.com";
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
          if cfg.backend == "qemu" then "qemu:///system"
          else "lxc:///";
      };

      defaultInstanceConfig = mkOption {
        type = types.attrs;
        default = {};
      };

      instances = mkOption {
        default = {};
        type = with types; attrsOf (submodule instanceOpts);
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
        } // genAttrs instNames (n: [ "log/${n}-console.log" ])
          // genAttrs instNames (n: [ "log/${n}-journal.log" ]);
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
            other libvirt machines (defined by the <code>instances</code>
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

    libvirt.test.instances.${cfg.test-driver.hostName} = {
      libvirt.name = mkForce "dom-@testid@";
      nixos.modules = cfg.test-driver.extraModules ++ [{
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
              if "${cfg.test-driver.script}" >> log/stdout 2>> log/stderr; then
                touch success
              else
                touch failed
              fi
              sync -f .
              ${pkgs.systemd}/bin/systemctl poweroff --force
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
          ${concatStrings (mapAttrsToList (n: i: ''
            ln -sv "${i.libvirt.xmlFile}" "$out/dom-${n}.xml"
          '') cfg.instances)}
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

      succeedOnFailure = true;

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

        # Variables that are substituted within the libvirt XML files
        testid="$(${pkgs.utillinux}/bin/uuidgen -r)"
        testid="''${testid%%-*}"
        testid="''${testid:0:7}"
        uid="$(id -u)"
        gid="$(id -g)"
        pwd="$(pwd)"
        starttime="$(now)"
        subnet="$(($RANDOM % 255))"

        function log() {
          printf "%05d %s\n" $(($(now) - $starttime)) "$1"
        }

        function err() {
          log "error: $1"
        }

        function run_one_build() {
          export build="$(readlink -m "$(mktemp -dp "$pwd")")"
          export mnt="$(readlink -m "$(mktemp -dp "$pwd")")"

          # Setup directories and libvirt XML files
          mkdir -p $build/{log,libvirt} $build/hosts/{${instList}}
          touch $build/log/std{out,err} $build/log/{${instList}}-console.log
          cp -t $build/libvirt "$src"/*
          for f in $build/libvirt/{dom,net}-*.xml; do substituteAllInPlace "$f"; done
          ${optionalString (cfg.backend == "lxc") ''mkdir $mnt/{root,run}-{${instList}} ''}

          # Let libvirt access paths inside the build directory and write to out dirs
          chmod a+x .
          chmod a+w -R $build

          log "Starting libvirt machines"
          ${pkgs.libvirt}/bin/virsh -c "${cfg.connectionURI}" \
            "${virshDestroyCmds}" &>/dev/null || true
          ${pkgs.libvirt}/bin/virsh -c "${cfg.connectionURI}" \
            "${virshCreateCmds}" >/dev/null
          ${pkgs.libvirt}/bin/virsh -c "${cfg.connectionURI}" \
            "event dom-$testid lifecycle --timeout ${toString cfg.timeouts.singleTryTimeout}" >/dev/null &
          export virshpid=$!

          ${concatStrings (flatten (mapAttrsToList (n: fs: map (f: ''
            prettytail "${padName n}" "$build/${f}" &
          '') fs) cfg.tailFiles))}

          wait $virshpid || true
        }

        while true; do
          run_one_build || true
          log "Destroying libvirt machines"
          ${pkgs.libvirt}/bin/virsh -c "${cfg.connectionURI}" \
            "${virshDestroyCmds}" &>/dev/null || true
          if [[ -a $build/success || -a $build/failed ]]; then
            break
          fi
          err "Build result unknown"
          if (($(date +%s) > ($starttime + ${toString cfg.timeouts.totalTimeout}))); then
            err "Total build timeout passed, will not retry"
            break
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
          for i in ${toString instNames}; do for l in console journal; do
            echo "file log $out/log/$i-$l.log"
          done; done
        ) >> $out/nix-support/hydra-build-products

        out=$out extra-build-steps || touch $out/failed

        if [[ -a $out/failed || ! -a $out/success ]]; then
          rm -f $out/failed $out/success
          exit 1
        fi
      '';
    };

  };

}
