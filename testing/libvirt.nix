{ config, pkgs, lib, ... }:

with lib;
with pkgs;

let

  cfg = config.libvirt.test;

  inherit (import ../lib.nix) hexByteToInt mkMAC;

  ips = mapAttrs (_: i: i.ip) cfg.instances;

  instanceOpts = { name, config, lib, ... }: {
    imports = [
      ../builders/libvirt.nix
      cfg.defaultInstanceConfig
    ];

    options = {
      ip = mkOption {
        type = types.str;
        default = let f = n: toString (hexByteToInt (
          substring n 2 (mkMAC name)
        )); in "10.0.${f 0}.${f 3}";
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
          rootPath = "root-${name}";
        };
        name = "${name}-@testid@";
        netdevs.eth0 = {
          mac = null;
          network = "net-@testid@";
        };
        consoleFile = "@build@/hosts/${name}/console.log";
        extraDevices = ''
          <serial type='file'>
            <source path='@build@/hosts/${name}/journal.log'/>
            <target port='1'/>
          </serial>
        '';
        fileShares.out = {
          guestPath = "/out";
          hostPath = if name == cfg.test-driver.hostName
                     then "/@build@" else "/@build@/hosts/${name}";
          readOnly = false;
        };
      };

      nixos.modules = singleton {
        services.nscd.enable = cfg.backend != "lxc";
        users.extraUsers.root.password = "root";
        services.journald.extraConfig = ''
          Storage=volatile
          ForwardToConsole=yes
          TTYPath=/dev/ttyS1
        '';
        networking = {
          hostName = name;
          firewall.enable = false;
          useDHCP = false;
          usePredictableInterfaceNames = false;
          localCommands = ''
            ip addr add ${config.ip}/16 dev eth0
            ip link set dev eth0 up
          '';
          extraHosts = concatStringsSep "\n" (mapAttrsToList (name: i:
            "${i.ip} ${concatStringsSep " " ([name] ++ (map (removeSuffix ".") i.extraHostNames))}"
          ) cfg.instances);
        };
      };
    };
  };

  instNames = attrNames cfg.instances;
  instList = concatMapStringsSep "," (n: ''"${n}"'') instNames;

  padName = n:
    if any (n': stringLength n' > stringLength n) (attrNames cfg.tailFiles)
    then padName "${n} " else n;

  virshCmds = concatStringsSep ";" (flatten [
    "net-create $build/libvirt/net-test.xml"
    (map (name: "create $build/libvirt/dom-${name}.xml --autodestroy") instNames)
    "event --timeout ${toString cfg.timeout} --domain $testid --event lifecycle"
    "net-destroy net-$testid"
  ]);

  # A temporary, isolated network for our test machines
  libvirtNetwork = writeText "network.xml" ''
    <network>
      <name>net-@testid@</name>
    </network>
  '';

in {

  options = {

    libvirt.test = {

      timeout = mkOption {
        type = types.int;
        default = 600;
      };

      out = {
        result = mkOption {
          type = types.path;
          description = ''
            The result of the test, as a nix derivation. This build
            fails if the verification script fails.
          '';
        };
        output = mkOption {
          type = types.path;
          description = ''
            The output produced by the test, as a nix derivation.
            This build always succeed.
          '';
        };
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

      verification-script = mkOption {
        type = types.lines;
        description = ''
          A script that will be inlined in the build phase of the
          result builder. The environment variable <code>output</output>
          will point to the directory containing the build output.
          By default, the output is checked for the existence of a
          successful exit code file from the test script.
          You can also use this script to do post-processing of the
          test output, by writing to the <code>out</code> path like
          any Nix build.
        '';
        default = ''
          if ! [ -a "$output/script.exit" ]; then
            echo >&2 "Test script exit code not found. Possible test timeout"
            exit 1
          fi
          ex="$(cat "$output/script.exit")"
          if ! [ "$ex" = "0" ]; then
            echo >&2 "Test script failed with exit code $ex"
            exit 1
          fi
        '';
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
        type = with types; attrsOf str;
        default = {
          OUT = "script.stdout";
          ERR = "script.stderr";
        } // genAttrs instNames (n: "hosts/${n}/console.log")
          // genAttrs instNames (n: "hosts/${n}/journal.log");
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
      libvirt.name = mkForce "@testid@";
      nixos.modules = cfg.test-driver.extraModules ++ [{
        systemd.services.test-script = {
          wantedBy = [ "multi-user.target" ];
          wants = [ "network.target" ];
          after = [ "network.target" ];
          path = cfg.test-driver.scriptPath;
          serviceConfig = {
            WorkingDirectory = "/out";
            Type = "oneshot";
            ExecStart = "${pkgs.writeScriptBin "test-script" ''
              #!${bash}/bin/bash
              "${cfg.test-driver.script}" >> script.stdout 2>> script.stderr
              echo "$?" > script.exit
              sync -f .
              ${pkgs.systemd}/bin/systemctl poweroff --force
            ''}/bin/test-script";
          };
        };
      }];
    };

    libvirt.test.out.result = pkgs.stdenv.mkDerivation {
      name = "test-result";

      phases = [ "buildPhase" ];

      buildPhase = ''
        export output="${cfg.out.output}"
        echo "Verifying test output $output"
        ${cfg.verification-script}
        test -a "$out" || mkdir "$out"
      '';
    };

    libvirt.test.out.output = pkgs.stdenv.mkDerivation {
      name = "test-output";

      src = runCommand "test-src" {} ''
        mkdir $out
        ${concatStrings (mapAttrsToList (n: i: ''
          ln -sv "${i.libvirt.xmlFile}" "$out/dom-${n}.xml"
        '') cfg.instances)}
        ln -s "${libvirtNetwork}" "$out/net-test.xml"
      '';

      phases = [ "buildPhase" ];

      buildPhase = ''
        function prettytail() {
          local header="$1"
          local file="$2"
          tail --pid $virshpid -F "$file" | while read l; do
            printf "%s %s\n" "$header" "$l"
          done
        }

        # Variables that are substituted within the libvirt XML files
        testid="$(basename "$out")"
        testid="''${testid%%-*}"
        build="$(pwd)/build"
        uid="$(id -u)"
        gid="$(id -g)"

        # Setup directories and libvirt XML files
        mkdir -p $build/libvirt $build/hosts/{${instList}}
        touch $build/hosts/{${instList}}/{console,journal}.log
        touch $build/script.std{out,err}
        cp -t $build/libvirt "$src"/*
        for f in $build/libvirt/{dom,net}-*.xml; do substituteAllInPlace "$f"; done
        ${optionalString (cfg.backend == "lxc") "mkdir root-{${instList}}"}

        # Let libvirt access paths inside the build directory and write to out dirs
        chmod a+x .
        chmod a+w $build $build/script.std{out,err} $build/hosts/*

        ${pkgs.libvirt}/bin/virsh -c "${cfg.connectionURI}" \
          "${virshCmds}" >/dev/null &
        virshpid=$!

        ${concatStrings (mapAttrsToList (n: f: ''
          prettytail "${padName n}" "$build/${f}" &
        '') cfg.tailFiles)}

        wait $virshpid || exit 1

        mkdir $out
        cp -r build/* $out/

        ${cfg.extraBuildSteps}
      '';
    };

  };

}
