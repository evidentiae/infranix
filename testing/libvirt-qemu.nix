{ config, pkgs, lib, ... }:

with lib;
with pkgs;

let

  cfg = config.libvirt.test;

  inherit (import ../lib.nix) hexByteToInt mkMAC;

  ips = mapAttrs (_: i: i.ip) cfg.instances;

  instanceOpts = { name, config, lib, ... }: {
    imports = [
      ../builders/libvirt-qemu.nix
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
        name = "${name}-@uuid@";
        netdevs.eth0 = {
          mac = null;
          network = "net-@uuid@";
        };
        consoleFile = "@pwd@/out/logs/${name}.console";
        extraDevices = ''
          <serial type='file'>
            <source path='@pwd@/out/logs/${name}.journal'/>
            <target port='1'/>
          </serial>
        '';
      };

      nixos.modules = singleton {
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
          interfaces.eth0.ip4 = singleton {
            prefixLength = 16;
            address = config.ip;
          };
          extraHosts = concatStringsSep "\n" (mapAttrsToList (name: i:
            "${i.ip} ${concatStringsSep " " ([name] ++ i.extraHostNames)}"
          ) cfg.instances);
        };
      };
    };
  };

  virshCmds = concatStringsSep ";" (flatten [
    "net-create out/libvirt/net-test.xml"
    (map (name: "create out/libvirt/dom-${name}.xml --autodestroy") (attrNames cfg.instances))
    "event --timeout ${toString cfg.timeout} --domain $uuid --event lifecycle"
    "net-destroy net-$uuid"
  ]);

  # A temporary, isolated network for our test machines
  libvirtNetwork = writeText "network.xml" ''
    <network>
      <name>net-@uuid@</name>
    </network>
  '';

in {

  options = {

    libvirt.test = {

      timeout = mkOption {
        type = types.int;
        default = 600;
      };

      out.result = mkOption {
        type = types.path;
      };

      connectionURI = mkOption {
        type = types.str;
        default = "qemu:///system";
      };

      defaultInstanceConfig = mkOption {
        type = types.attrs;
        default = {};
      };

      instances = mkOption {
        default = {};
        type = with types; attrsOf (submodule instanceOpts);
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
      libvirt.name = mkForce "@uuid@";
      libvirt.fileShares.out = {
        guestPath = "/out";
        hostPath = "out";
        readOnly = false;
      };
      nixos.modules = cfg.test-driver.extraModules ++ [{
        systemd.services.test-driver = {
          wantedBy = [ "multi-user.target" ];
          wants = [ "network.target" ];
          after = [ "network.target" ];
          path = cfg.test-driver.scriptPath;
          serviceConfig = {
            WorkingDirectory = "/out";
            Type = "oneshot";
            ExecStart = "${pkgs.writeScriptBin "test-driver" ''
              #!${bash}/bin/bash
              "${cfg.test-driver.script}" > stdout.log 2> stderr.log && \
                touch passed
              touch done
              sync -f .
              ${pkgs.systemd}/bin/systemctl poweroff --force
            ''}/bin/test-driver";
          };
        };
      }];
    };

    libvirt.test.out.result = pkgs.stdenv.mkDerivation {
      name = "libvirt-test-result";

      src = runCommand "test-src" {} ''
        mkdir $out
        ${concatStrings (mapAttrsToList (n: i: ''
          ln -sv "${i.libvirt.xmlFile}" "$out/dom-${n}.xml"
        '') cfg.instances)}
        ln -sv  "${libvirtNetwork}" "$out/net-test.xml"
      '';

      buildInputs = with pkgs; [ gnugrep libvirt procps utillinux ];

      phases = [ "buildPhase" ];

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

        uuid="$(uuidgen -r)"
        pwd="$(pwd)"

        echo "Test UUID: $uuid"

        mkdir -p out/logs out/libvirt
        touch out/logs/{${concatMapStringsSep "," (n: ''"${n}"'')
          (attrNames cfg.instances)}}.{console,journal}
        cp -t out/libvirt "$src"/*

        for f in out/libvirt/{dom,net}-*.xml; do substituteAllInPlace "$f"; done

        # Let qemu access paths inside the build directory and write to out dir
        chmod a+x .
        chmod a+w out

        tail -Fq out/stdout.log out/stderr.log \
          ${concatMapStringsSep " " (n: "out/logs/${n}.journal")
            (attrNames cfg.instances)
          } 2>/dev/null &

        # Start libvirt machines
        virsh -c "${cfg.connectionURI}" "${virshCmds}" >/dev/null || true

        test -a out/done || echo >&2 "Possible test timeout!"
        test -a out/passed || exit 1

        chmod go-w out
        mv out $out
      '';
    };

  };

}
