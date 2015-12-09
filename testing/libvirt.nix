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
        consoleFile = "@pwd@/out/hosts/${name}/console.log";
        extraDevices = ''
          <serial type='file'>
            <source path='@pwd@/out/hosts/${name}/journal.log'/>
            <target port='1'/>
          </serial>
        '';
        fileShares.out = {
          guestPath = "/out";
          hostPath = "out/hosts/${name}";
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
            "${i.ip} ${concatStringsSep " " ([name] ++ i.extraHostNames)}"
          ) cfg.instances);
        };
      };
    };
  };

  instNames = attrNames cfg.instances;
  instList = concatMapStringsSep "," (n: ''"${n}"'') instNames;

  virshCmds = concatStringsSep ";" (flatten [
    "net-create out/libvirt/net-test.xml"
    (map (name: "create out/libvirt/dom-${name}.xml --autodestroy") instNames)
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
          test -a hosts/test-driver/script.exit && \
          test "$(cat hosts/test-driver/script.exit)" = "0" || \
          exit 1
        '';
      };

      test-driver = {
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

    libvirt.test.instances.test-driver = {
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
              "${cfg.test-driver.script}" > script.stdout 2> script.stderr
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
        ln -sv  "${libvirtNetwork}" "$out/net-test.xml"
      '';

      phases = [ "buildPhase" "installPhase" "fixupPhase" ];

      buildPhase = ''
        function cleanup() {
          local jobs="$(jobs -p)"
          test -n "$jobs" && kill $jobs || true
        }

        function waitForFile() {
          local file="$1"
          local n=0
          while [[ ! -a "$file" ]] && (($n < ${toString cfg.timeout})); do
            n=$((n+1))
            sleep 1
          done
          if ! [ -a "$file" ]; then return 1; fi
        }

        trap cleanup SIGTERM SIGKILL EXIT

        # Variables that are substituted within the libvirt XML files
        testid="$(basename "$out")"
        testid="''${testid%%-*}"
        pwd="$(pwd)"
        uid="$(id -u)"
        gid="$(id -g)"

        # Setup directories and libvirt XML files
        mkdir -p out/libvirt out/hosts/{${instList}}
        touch out/hosts/{${instList}}/{console,journal}.log
        cp -t out/libvirt "$src"/*
        for f in out/libvirt/{dom,net}-*.xml; do substituteAllInPlace "$f"; done
        ${optionalString (cfg.backend == "lxc") "mkdir root-{${instList}}"}

        # Let libvirt access paths inside the build directory and write to out dir
        chmod a+x .
        chmod a+w out/hosts/*

        tail -Fq out/hosts/test-driver/script.std{out,err} \
          out/hosts/{${instList}}/{console,journal}.log 2>/dev/null &

        ${pkgs.libvirt}/bin/virsh -c "${cfg.connectionURI}" \
          "${virshCmds}" >/dev/null || true

        cleanup
      '';

      installPhase = "mv out $out";
    };

  };

}
