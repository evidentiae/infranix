{ config, lib, ... }:

with lib;
with builtins;

{

  nixpkgs.config.packageOverrides = pkgs: rec {

    writeHaskellScript = name: {
      pkgfun ? (_: []), buildInputs ? [], extraModules ? [], hlint ? true,
      ghcopts ? [
        "-static" "-threaded" "-Wall" "-fno-warn-missing-signatures"
        "-fwarn-unused-imports" "-Werror"
      ]
    }: script: pkgs.stdenv.mkDerivation {
      inherit name ghcopts hlint;

      phases = [ "buildPhase" "installPhase" "fixupPhase" ];

      buildInputs = buildInputs ++ [
        pkgs.binutils
        (pkgs.haskellPackages.ghcWithPackages pkgfun)
      ] ++ optional hlint pkgs.haskellPackages.hlint;

      src = pkgs.linkFarm "${name}-src" (
        [{ name = "${name}.hs"; path = toFile "${name}.hs" script; }] ++
        imap (i: m: { name = "mod${toString i}.hs"; path = m; }) extraModules
      );

      buildPhase = ''
        ln -s $src src
        test "$hlint" == "1" && hlint src
        ghc --make -O2 -outputdir . -tmpdir . -o "./$name" \
          $ghcopts src/*
        strip -s "$name"
      '';

      stripAllList = [ "." ];

      installPhase = ''
        mv "$name" $out
      '';
    };

    writeHaskellScriptBin = name: args: script: pkgs.stdenv.mkDerivation {
      inherit name;
      phases = [ "installPhase" ];
      script = writeHaskellScript name args script;
      installPhase = ''
        mkdir -p $out/bin
        ln -s "$script" "$out/bin/$name"
      '';
    };

  };
}
