{ config, pkgs, lib, ... }:

with lib;
with pkgs;

let

  cfg = config.libvirt.test;

  inherit (import ../lib.nix) hexByteToInt mkMAC;

  ips = mapAttrs (name: _:
    let f = n: toString (hexByteToInt (
      substring n 2 (mkMAC "libvirt-test-${name}")
    )); in "${cfg.subnet}.${f 0}.${f 3}"
  ) cfg.instances;

  instanceOpts = { name, config, lib, ... }: {
    imports = [
      ../builders/libvirt-qemu.nix
      cfg.defaultInstanceConfig
    ];

    config = {
      _module.args = { inherit pkgs; };

      libvirt.name = "libvirt-test-${name}";

      libvirt.netdevs.eth0 = {};

      nixos.modules = singleton {
        networking = {
          hostName = name;
          firewall.enable = false;
          useDHCP = false;
          interfaces.eth0.ip4 = singleton {
            prefixLength = 16;
            address = ips.${name};
          };
          extraHosts = concatStringsSep "\n" (
            mapAttrsToList (name: ip: "${ip} ${name}") ips
          );
        };
      };
    };
  };

in {

  imports = [
  ];

  options = {

    libvirt.test = {

      timeout = mkOption {
        type = types.str;
        default = "10m";
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
              ${pkgs.systemd}/bin/systemctl poweroff
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
        mkdir -p out/console-logs

        # Hack to let qemu access paths inside the build directory
        chmod a+x .

        # I don't know why this is needed. I haven't figured out which
        # user qemu really is running as. It looks like root, but it still
        # can't write to the "out" dir.
        chmod a+w out

        function launchVM() {
          local name="$1"
          local xml="$2"
          sed s,@PWD@,"$(pwd)/",g "$xml" > "$name.xml"
          echo >&2 "[$name] Launching VM"
          local virshcmd='virsh -c "${cfg.connectionURI}" create "$name.xml"'
          local virshopts="--autodestroy --console"
          script -c "timeout -s9 ${cfg.timeout} $virshcmd $virshopts" \
            "out/console-logs/$name" >/dev/null || true &
        }

        ${concatStrings (mapAttrsToList (name: inst: ''
          launchVM "${name}" "${inst.libvirt.xmlFile}"
          ${optionalString (name == "test-driver") "testvmpid=$!"}
        '') cfg.instances)}

        tail -Fq out/stdout.log out/stderr.log 2>/dev/null &

        wait $testvmpid

        killpids="$(pgrep -u $(id -un) virsh) $(jobs -rp)"
        if [ -n "$killpids" ]; then
          kill -9 $killpids
          wait $killpids 2>/dev/null || true
        fi

        if ! [ -a out/done ]; then
          echo >&2 "Possible test timeout!"
        fi

        if ! [ -a out/passed ]; then
          ${concatStrings (mapAttrsToList (name: inst: ''
            echo >&2 "[${name}] VM console log:"
            cat >&2 "out/console-logs/${name}"
          '') cfg.instances)}
          exit 1
        fi

        rm -f out/{done,passed}
        chmod go-w out
        mv out $out
      '';
    };

  };

}
