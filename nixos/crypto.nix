{ pkgs, config, lib, ... }:

with pkgs;
with lib;
with builtins;

let

  topConfig = config;
  cfg = config.crypto;

  decryptSecretScript = { secret, path, user, group }: ''
    mkdir -p "$(dirname "${path}")"
    touch "${path}"
    chmod ${if group == "root" then "0400" else "0440"} "${path}"
    chown "${user}"."${group}" "${path}"
    ${if cfg.dummy then ''
      echo "copying dummy secret ${secret.dummyContents} to ${path}"
      cat "${secret.dummyContents}" > "${path}"
    '' else ''
      echo "decrypting ${path}"
      ${cfg.decrypter} "${encryptSecret secret}" > "${path}"
    ''}
  '';

  decryptSecretsScript = svcName: writeScript "decrypt-secrets-${svcName}" ''
    #!${bash}/bin/bash
    ${concatMapStrings ({svc,secretName,secret}:
      decryptSecretScript {
        inherit secret;
        inherit (svc) path user group;
      }
    ) (secretsForService svcName)}
  '';

  encryptSecret = secret: toFile "sec" (readFile (stdenv.mkDerivation {
    name = "encryptedsecret";
    phases = [ "buildPhase" ];
    preferLocalBuild = true;
    buildPhase = ''
      ${cfg.encrypter} "${secret.plaintextPath}" > "$out"
    '';
  }));

  secretSvcOpts = secretName: secret: { name, config, ... }: {
    options = {
      path = mkOption {
        type = types.str;
      };
      user = mkOption {
        type = types.str;
        default =
          if topConfig.systemd.services ? ${name}.serviceConfig.User
          then topConfig.systemd.services.${name}.serviceConfig.User
          else "root";
      };
      group = mkOption {
        type = types.str;
        default = "root";
      };
    };
    config = {
      path = "/run/secrets/${secretName}.${name}";
    };
  };

  secretOpts = { name, config, ... }: {
    options = {
      services = mkOption {
        type = with types; attrsOf (submodule (secretSvcOpts name config));
        default = {};
      };
      plaintextPath = mkOption {
        type = types.str;
      };
      dummyContents = mkOption {
        type = types.package;
      };
    };
  };

  # String -> [{svc,secretName,secret}]
  secretsForService = svcName: flatten (mapAttrsToList (secretName: secret:
    let svc = findFirst ({name,value}: name == svcName) [] (
      mapAttrsToList nameValuePair secret.services
    ); in
      if svc == [] then []
      else { svc = svc.value; inherit secretName secret; }
  ) cfg.secrets);

  svcNames = unique (
    concatMap (s: attrNames s.services) (attrValues cfg.secrets)
  );

  dependentServices = map (svcName: {
    ${svcName} = {
      restartTriggers = singleton (hashString "sha256" (
        "${decryptSecretsScript svcName}"
      ));
    };
  }) svcNames;

  decryptServices = map (svcName: {
    "secrets-for-${svcName}" = rec {
      wantedBy = [ "${svcName}.service" ];
      before = wantedBy;
      script = "${decryptSecretsScript svcName}";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  }) svcNames;

  purgeOldSecrets = singleton {
    purge-old-secrets = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        ${findutils}/bin/find /run/secrets -type f | ${gnugrep}/bin/grep -vf ${
          writeText "secret-paths" (
            concatStringsSep "\n" (concatMap (svcName:
              map ({svc,...}: svc.path) (secretsForService svcName)
            ) svcNames)
          )
        } | ${findutils}/bin/xargs -r rm -v
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };

  mkDecryptWrapper = secretNames: writeScript "decrypt-wrapper" ''
    #!${bash}/bin/bash
    set -eu

    PATH="${utillinux}/bin:$PATH"

    if ! [ "$(id -u)" == "0" ]; then
      echo >&2 "You must be root"
      exit 1
    fi

    newroot="$(mktemp -d)"
    chmod 0700 "$newroot"

    function cleanup() {
      umount -l "$newroot"/{dev/pts,dev/shm,dev,nix/store,proc,sys,var,etc,root,run}
      rm -rf "$newroot"
    }

    mkdir "$newroot/secrets"
    for d in nix/store dev dev/pts dev/shm proc sys var etc root; do
      mkdir -p "$newroot/$d"
      mount --bind "/$d" "$newroot/$d"
    done
    mkdir -p "$newroot/run"
    mount --rbind "/run" "$newroot/run"

    trap cleanup SIGINT SIGTERM EXIT

    chroot "$newroot" "${writeScript "wrapped" ''
      #!${bash}/bin/bash
      set -eu
      ${concatMapStrings (s: let secret = cfg.secrets.${s}; in
        decryptSecretScript {
          inherit secret;
          path = "/secrets/${s}";
          user = "root";
          group = "root";
        }
      ) secretNames}
      exec "$@"
    ''}" "$@"
  '';


in {

  options = {

    crypto = {
      dummy = mkOption {
        type = types.bool;
        default = false;
      };
      decrypter = mkOption {
        type = types.path;
        description = ''
          Executable that can decrypt a secret. The first argument will be
          the encrypted file. The decrypted plaintext should be printed on
          stdout.
        '';
      };
      encrypter = mkOption {
        type = types.path;
        description = ''
          Executable that can encrypt a secret. The first argument will be
          the plaintext file. The encrypted ciphertext should be printed on
          stdout. The encrypter will run during the evalutation phase.
        '';
      };
      secrets = mkOption {
        type = with types; attrsOf (submodule secretOpts);
        default = {};
      };
      mkDecryptWrapper = mkOption {
        type = types.unspecified;
        default = mkDecryptWrapper;
      };
    };

  };

  config = mkIf (config.crypto.secrets != {}) {
    systemd.services = mkMerge (
      dependentServices ++ decryptServices ++ purgeOldSecrets
    );
  };

}
