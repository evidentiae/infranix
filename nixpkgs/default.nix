self: super:

with builtins;

{
  infranix = self.callPackage ./infranix {};

  writeHaskellScript = name: {
    pkgfun ? (_: []), buildInputs ? [], extraModules ? [], hlint ? true,
    ghcopts ? [
      "-static" "-threaded" "-Wall" "-fno-warn-missing-signatures"
      "-fwarn-unused-imports" "-Werror"
    ]
  }: script: super.stdenv.mkDerivation {
    inherit name ghcopts hlint;

    phases = [ "buildPhase" "installPhase" "fixupPhase" ];

    buildInputs = buildInputs ++ [
      self.binutils
      (self.haskellPackages.ghcWithPackages pkgfun)
    ] ++ super.lib.optional hlint self.haskellPackages.hlint;

    src = super.linkFarm "${name}-src" (
      [{ name = "${name}.hs"; path = toFile "${name}.hs" script; }] ++
      super.lib.imap (i: m: { name = "mod${toString i}.hs"; path = m; }) extraModules
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

  writeHaskellScriptBin = name: args: script: super.stdenv.mkDerivation {
    inherit name;
    phases = [ "installPhase" ];
    script = self.writeHaskellScript name args script;
    installPhase = ''
      mkdir -p $out/bin
      ln -s "$script" "$out/bin/$name"
    '';
  };

  nixos-multi-spawn = self.haskellPackages.callPackage (super.fetchFromGitHub {
    owner = "evidentiae";
    repo = "nixos-multi-spawn";
    rev = "d1decff1c85630db2b3baf0247d683d9e5a8c7ef";
    sha256 ="13806mqf11cpdr1gypn8wwaz4gpyrd6j3lddmcr62hsfp2rarnc8";
  }) {};

}
