{ config, lib, pkgs, ... }:

with pkgs;
with lib;
with builtins;

let

  cfg = config.cli;

  # TODO replace 'sub' with something nicer that can just take a JSON
  # description of the available commands. Due to limitations in 'sub'
  # we have to rebuild the whole sub each time a single command has been
  # modified, and we have to copy commands into the sub's libexec

  sub = fetchFromGitHub {
    owner = "basecamp";
    repo = "sub";
    rev = "bb93f151df9e4219ae4153c83aad63ee6494a5d8";
    sha256 = "0k5jw0783pbxfwixrh8c8iic8v9xlgxbyz88z1jiv5j6xvy2v9m7";
  };

  stepOpts = {name, config, ... }: {
    options = {
      binary = mkOption {
        type = with types; nullOr path;
        default = null;
      };
      dependencies = mkOption {
        type = with types; listOf str;
        default = [];
      };
      interactive = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  mkSub = name: subCommands: stdenv.mkDerivation {
    inherit name;

    src = sub;

    buildInputs = [ bash makeWrapper ];

    phases = [ "buildPhase" "fixupPhase" ];

    dontStrip = true;

    buildPhase = ''
      cp -r "$src" $out
      chmod u+w -R $out
      cd $out

      ./prepare.sh "$name" >/dev/null
      for prog in $out/bin/* $out/libexec/*; do
        wrapProgram "$prog" \
          --prefix PATH : ${stdenv.lib.makeBinPath [gnused gawk ncurses]}
      done

      mkdir -p nix-support
      ./bin/"$name" init - > nix-support/setup-hook
      rm -rf share libexec/"$name"-init

      ${concatStrings (mapAttrsToList (subName: cmd:
        optionalString (cmd.binary != null) ''
          cp -T "${cmd.binary}" "$out/libexec/$name-${subName}"
        ''
      ) subCommands)}
    '';
  };

  safeName = replaceStrings [":" " " "/"] ["_" "_" "_"];

  makefile = name: steps:
    writeText "Makefile" (concatStrings (
      mapAttrsToList (stepName: step: let target = safeName stepName; in ''
        .PHONY${optionalString step.interactive " .NOTPARALLEL"}: ${target}
        ${target}: ${toString (map safeName step.dependencies)}
        ''\t@echo >&2 "> ${name}:${stepName}"
        ${if step.binary == null then "" else "\t@${step.binary} $(cmdargs)"}
      '') steps ++ singleton ''
        all: ${toString (map safeName (attrNames steps))}
      ''
    ));

  mkSteps = name: bin: maxjobs: steps:
    (if bin then writeScriptBin else writeScript) (safeName name) ''
      #!${stdenv.shell}
      exec ${gnumake}/bin/make cmdargs="$*" -j ${toString maxjobs} \
        --no-print-directory -f ${makefile name steps} all
    '';

  subCmdOpts = parentName: { name, config, ... }: {
    options = {
      binary = mkOption {
        type = with types; nullOr path;
        default = null;
      };
      steps = mkOption {
        type = with types; attrsOf (submodule stepOpts);
        default = {};
      };
      maxParallelism = mkOption {
        type = with types; nullOr int;
        default = null;
      };
    };
    config = {
      binary = mkIf (config.steps != {}) (
        mkSteps "${parentName}:${name}" false config.maxParallelism config.steps
      );
    };
  };

  commandOpts = { name, config, ... }: {
    options = {
      subCommands = mkOption {
        type = with types; attrsOf (submodule (subCmdOpts name));
        default = {};
      };

      steps = mkOption {
        type = with types; attrsOf (submodule stepOpts);
        default = {};
      };

      maxParallelism = mkOption {
        type = with types; nullOr int;
        default = null;
      };

      package = mkOption {
        type = types.package;
        default = with config; (
          if subCommands == {} && steps == {} then
            throw "The command ${name} has no sub commands or steps defined"
          else if subCommands != {} && steps != {} then
            throw "The command ${name} has both sub commands and steps defined"
          else if subCommands != {} then mkSub name subCommands
          else mkSteps name true config.maxParallelism steps
        );
      };
    };
  };

in {
  imports = [
    ./assertions.nix
  ];

  options = {
    cli = {
      build.nix-shell = mkOption {
        type = types.package;
      };

      nix-shell = {
        shellHook = mkOption {
          type = types.lines;
          default = "";
        };
        buildInputs = mkOption {
          type = types.listOf types.package;
          default = [];
        };
        environment = mkOption {
          type = types.attrs;
          default = {};
        };
      };

      commands = mkOption {
        type = with types; attrsOf (submodule commandOpts);
        default = {};
      };
    };
  };

  config = {
    cli.build.nix-shell = mkDefault (
      if cfg.commands == {} then throw "No cli commands defined" else config.withAssertions (
        pkgs.runCommand "cli" (cfg.nix-shell.environment // {
          inherit (cfg.nix-shell) shellHook;
          buildInputs =
            cfg.nix-shell.buildInputs ++
            map (cmd: cmd.package) (attrValues cfg.commands);
        }) ""
      )
    );

    cli.nix-shell.shellHook = ''
      if [ -n "$RELOADER_PID" ]; then
        reload() {
          kill -1 "$RELOADER_PID"
          exit &>/dev/null
        }
      fi
    '';
  };
}
