self: super:

with builtins;

{
  infranix = self.callPackage ./infranix {};

  nixos-rebuild-with-paths = super.substituteAll {
    name = "nixos-rebuild-with-paths";
    dir = "bin";
    isExecutable = true;
    src = ./nixos-rebuild-with-paths;
    lib = ../lib;
  };

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
    rev = "09388f0555e76d418a798bc4a53fc84fdf0cd6ac";
    sha256 ="19q0w9zy9nlw5m21r1ksqg6fzlmxzwyjyw26k33x0q1ba465jc0s";
  }) {};

}
