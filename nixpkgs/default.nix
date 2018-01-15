self: super:

with builtins;

{
  nix-path = self.haskellPackages.callPackage (
    super.fetchFromGitHub {
      owner = "imsl";
      repo = "nix-path";
      rev = "fb2dc3d2375d7b895153344cddd98f53611ab3bd";
      sha256 ="1l3drl5ixvz5bbmcmniwx1vk6nspadaxax61hvrcqr90iysny27d";
    }
  ) {
    pipes-concurrency = self.haskellPackages.pipes-concurrency_2_0_8;
    hnix = super.haskell.lib.appendPatch super.haskellPackages.hnix (
      super.fetchurl {
        url = "https://patch-diff.githubusercontent.com/raw/jwiegley/hnix/pull/66.patch";
        sha256 = "05w440xmdiz9syadbnclwk45jxpvbyzm5vwiiaw88yl16m5w1qm0";
      }
    );
  };

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
}
