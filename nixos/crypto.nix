{ pkgs, config, lib, ... }:

with pkgs;
with lib;
with builtins;

let

  topConfig = config;

  decryptSecretScript = secret: svc: writeScript "decrypt-secret" ''
    #!${bash}/bin/bash
    mkdir -p "$(dirname "${svc.path}")"
    touch "${svc.path}"
    chmod ${if svc.group == "root" then "0400" else "0440"} "${svc.path}"
    chown "${svc.user}"."${svc.group}" "${svc.path}"
    echo "decrypting ${svc.path}"
    ${config.crypto.decrypter} "${encryptSecret secret}" > "${svc.path}"
  '';

  encryptSecret = secret: toFile "sec" (readFile (stdenv.mkDerivation {
    name = "encryptedsecret";
    phases = [ "buildPhase" ];
    preferLocalBuild = true;
    buildPhase = ''
      ${config.crypto.encrypter} "${secret.plaintextPath}" > "$out"
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
    };
  };

  allSecretSvcs = flatten (mapAttrsToList (secretName: secret:
    mapAttrsToList
      (svcName: svc: { inherit secretName secret svcName svc; })
      secret.services
  ) config.crypto.secrets);

  dependentServices = map ({secretName, secret, svcName, svc}: {
    ${svcName} = {
      restartTriggers = singleton (decryptSecretScript secret svc);
    };
  }) allSecretSvcs;

  decryptServices = mapAttrsToList (secretName: secret: {
    "secret-${secretName}" = rec {
      wantedBy = map (s: s+".service") (attrNames secret.services);
      before = wantedBy;
      script = concatMapStringsSep "\n"
                 (svc: decryptSecretScript secret svc)
                 (attrValues secret.services);
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  }) config.crypto.secrets;

  purgeOldSecrets = singleton {
    purge-old-secrets = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        ${findutils}/bin/find /run/secrets -type f | ${gnugrep}/bin/grep -vf ${
          writeText "secret-paths" (
            concatMapStringsSep "\n" (s: s.svc.path) allSecretSvcs
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
