{ config, pkgs, lib, ... }:

with lib;

let

  cfg = config.runner;

  makefile = pkgs.writeText "makefile" (concatStrings (mapAttrsToList (cmd: steps: ''
    .PHONY: ${cmd}
    ${cmd}: ${cmd}${toString (length steps)}

    .PHONY: ${cmd}0
    ${cmd}0:

    ${concatImapStrings (i: substeps: ''
      .PHONY: ${cmd}${toString i}
      ${cmd}${toString i}: ${concatStringsSep " "
        (imap (j: _: "${cmd}${toString i}${toString j}") substeps)
      }

      ${concatImapStrings (j: script:
        let
          stepStr = optional (length steps > 1) "${toString i}/${toString (length steps)}";
          subStepStr = optional (length substeps > 1) "${toString j}/${toString (length substeps)}";
        in ''
          .PHONY: ${cmd}${toString i}${toString j}
          ${cmd}${toString i}${toString j}: ${cmd}${toString (i - 1)}
          ''\t@echo >&2 "> ${cmd} ${concatStringsSep "." (stepStr ++ subStepStr)}"
          ''\t@${script} $(cmdargs)
        ''
      ) substeps}
    '') steps}
  '') cfg.commands));

in {
  runner.out = mkIf (config.runner.backend == "make") (
    pkgs.writeScript "make-runner" ''
      #!${pkgs.bash}/bin/bash
      cmd="$1"
      if [ -z "$cmd" ]; then
        echo >&2 "No command specified"
        exit 1
      fi
      shift
      exec ${pkgs.gnumake}/bin/make cmdargs="$*" -Oline -j -f ${makefile} "$cmd"
    ''
  );
}
