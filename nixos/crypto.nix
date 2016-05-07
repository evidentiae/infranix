{ pkgs, config, lib, ... }:

with pkgs;
with lib;
with builtins;

let

  topConfig = config;
  cfg = config.crypto;

  decryptSecretsScript = svcName: writeScript "decrypt-secrets-${svcName}" ''
    #!${bash}/bin/bash
    ${concatMapStrings ({svc,secretName,secret}: ''
      mkdir -p "$(dirname "${svc.path}")"
      touch "${svc.path}"
      chmod ${if svc.group == "root" then "0400" else "0440"} "${svc.path}"
      chown "${svc.user}"."${svc.group}" "${svc.path}"
      ${if cfg.dummy then ''
        echo "copying dummy secret ${secret.dummyContents} to ${svc.path}"
        cat "${secret.dummyContents}" > "${svc.path}"
      '' else if hasPrefix storeDir secret.plaintextPath then ''
        echo "copying plaintext ${secret.plaintextPath} to ${svc.path}"
        cat "${secret.plaintextPath}" > "${svc.path}"
      '' else ''
        echo "decrypting ${svc.path}"
        ${cfg.decrypter} "${encryptSecret secret}" > "${svc.path}"
      ''}
    '') (secretsForService svcName)}
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
    };

  };

  config = mkIf (config.crypto.secrets != {}) {
    systemd.services = mkMerge (
      dependentServices ++ decryptServices ++ purgeOldSecrets
    );
  };

}
