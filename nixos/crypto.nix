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
      ${cfg.decrypter} "${secret.encryptedPath}" > "${path}"
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
      encryptedPath = mkOption {
        type = types.path;
      };
      dummyContents = mkOption {
        type = types.path;
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
        mkdir -p /run/secrets
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

  mkDecryptWrapper = secretNames: writeScript "decrypt-wrapper" (
    if cfg.dummy then ''
      #!${bash}/bin/bash
      exec "$@"
    '' else ''
      #!${bash}/bin/bash
      set -eu

      PATH="${utillinux}/bin:$PATH"

      if ! [ "$(id -u)" == "0" ]; then
        echo >&2 "You must be root"
        exit 1
      fi

      root="$(mktemp -d)"

      function cleanup() {
        umount --recursive "$root"
        rmdir "$root"
      }

      trap cleanup SIGINT SIGTERM EXIT

      mount -t tmpfs -o mode=700 tmpfs "$root"
      mkdir "$root"/{proc,tmp,secrets}
      mount -t proc proc "$root/proc"

      for d in nix/store var etc root; do
        mkdir -p "$root/$d"
        mount  --make-rslave --bind "/$d" "$root/$d"
      done
      for d in run sys dev; do
        mkdir -p "$root/$d"
        mount --make-rslave --rbind "/$d" "$root/$d" || true
      done

      chroot "$root" "${writeScript "wrapped" ''
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
    '');

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

    system.activationScripts = mkIf cfg.dummy {
      install-dummy-secrets.deps = [];
      install-dummy-secrets.text = ''
        mkdir -p /secrets
        ${concatMapStrings ({name, value}:
          decryptSecretScript {
            secret = value;
            path = "/secrets/${name}";
            user = "root";
            group = "root";
          }
        ) (mapAttrsToList nameValuePair cfg.secrets)}
      '';
    };
  };
}
