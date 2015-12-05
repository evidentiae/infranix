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
        name = "libvirt-test-${name}";
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
        mkdir -p out/logs

        # Hack to let qemu access paths inside the build directory
        chmod a+x .

        # I don't know why this is needed. I haven't figured out which
        # user qemu really is running as. It looks like root, but it still
        # can't write to the "out" dir.
        chmod a+w out

        function destroyVMs() {
          ${concatStrings (mapAttrsToList (_: inst: ''
            virsh -c "${cfg.connectionURI}" destroy "${inst.libvirt.name}" || true
          '') cfg.instances)}
          kill $(jobs -p) || true
        }

        trap destroyVMs SIGTERM SIGKILL EXIT

        ${concatStrings (mapAttrsToList (name: inst: ''
          sed s,@PWD@,"$(pwd)/",g "${inst.libvirt.xmlFile}" > "${name}.xml"
          touch "out/logs/${name}."{console,journal}
          virsh -c "${cfg.connectionURI}" create "${name}.xml"
        '') cfg.instances)}

        tail -Fq out/stdout.log out/stderr.log \
          ${concatMapStringsSep " " (n: "out/logs/${n}.journal")
            (attrNames cfg.instances)
          } 2>/dev/null &

        n=0
        while [[ ! -a out/done ]] && (($n < ${toString cfg.timeout})); do
          n=$((n+1))
          sleep 1
        done

        chmod go-w out

        if ! [ -a out/done ]; then
          echo >&2 "Possible test timeout!"
        fi

        if ! [ -a out/passed ]; then
          exit 1
        fi

        rm -f out/{done,passed}
        mv out $out

        destroyVMs
      '';
    };

  };

}
