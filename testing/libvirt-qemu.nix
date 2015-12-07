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
          substring n 2 (mkMAC "libvirt-test-${name}")
        )); in "${cfg.subnet}.${f 0}.${f 3}";
      };

      extraHostNames = mkOption {
        type = with types; listOf str;
        default = [];
      };
    };

    config = {
      _module.args = { inherit pkgs; };

      libvirt = {
        name = "${name}-__RAND__";
        netdevs.eth0 = {};
        consoleFile = "@PWD@/out/logs/${name}.console";
        extraDevices = ''
          <serial type='file'>
            <source path='@PWD@/out/logs/${name}.journal'/>
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

in {

  options = {

    libvirt.test = {

      timeout = mkOption {
        type = types.int;
        default = 600;
      };

      subnet = mkOption {
        type = types.str;
        default = "10.111";
      };

      script = mkOption {
        type = types.path;
      };

      scriptPath = mkOption {
        type = with types; listOf path;
        default = [];
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

    };

  };

  config = {

    libvirt.test.instances.test-driver = {
      libvirt.name = mkForce "__RAND__";
      libvirt.fileShares.out = {
        guestPath = "/out";
        hostPath = "out";
        readOnly = false;
      };
      nixos.modules = singleton {
        systemd.services.test-driver = {
          wantedBy = [ "multi-user.target" ];
          wants = [ "network.target" ];
          after = [ "network.target" ];
          path = cfg.scriptPath;
          serviceConfig = {
            WorkingDirectory = "/out";
            Type = "oneshot";
            ExecStart = "${pkgs.writeScriptBin "test" ''
              #!${bash}/bin/bash
              echo "[test-driver] Running test script" > stdout.log
              "${cfg.script}" > >(tee -a stdout.log) \
                2> >(tee -a stderr.log >&2) && touch passed
              touch done
              echo "[test-driver] Test script done" >> stdout.log
            ''}/bin/test";
          };
        };
      };
    };

    libvirt.test.out.result = pkgs.stdenv.mkDerivation {
      name = "libvirt-test-result";

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

        mkdir -p out/logs

        # Hack to let qemu access paths inside the build directory
        chmod a+x .

        # I don't know why this is needed. I haven't figured out which
        # user qemu really is running as. It looks like root, but it still
        # can't write to the "out" dir.
        chmod a+w out

        uuid="$(uuidgen -r)"

        # Prepare libvirt XML files
        ${concatStrings (mapAttrsToList (name: inst: ''
          sed s,@PWD@,"$(pwd)/",g "${inst.libvirt.xmlFile}" | \
          sed s,__RAND__,"$uuid",g > "${name}.xml"
          touch "out/logs/${name}."{console,journal}
        '') cfg.instances)}

        # Start libvirt machines
        virsh -c "${cfg.connectionURI}" \
          "${concatStringsSep ";" (mapAttrsToList (name: inst:
            "create ${name}.xml --autodestroy"
          ) cfg.instances)}; event --domain "$uuid" --event reboot" &

        tail -Fq out/stdout.log out/stderr.log \
          ${concatMapStringsSep " " (n: "out/logs/${n}.journal")
            (attrNames cfg.instances)
          } 2>/dev/null &

        waitForFile out/done || echo >&2 "Possible test timeout!"

        test -a out/passed || exit 1

        rm -f out/{done,passed}
        chmod go-w out
        mv out $out
      '';
    };

  };

}
