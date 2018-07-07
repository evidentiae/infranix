self: super:

with builtins;

{
  haskellPackages = super.haskellPackages.override {
    overrides = self: _: {
      hweblib = super.haskell.lib.dontCheck super.haskellPackages.hweblib;

      # Copied form nixpkgs master @ 2018-04-30
      "hnix" = self.callPackage
        ({ mkDerivation, ansi-wl-pprint, base, containers, criterion
         , data-fix, deepseq, deriving-compat, parsers, regex-tdfa
         , regex-tdfa-text, semigroups, tasty, tasty-hunit, tasty-th, text
         , transformers, trifecta, unordered-containers
         }:
         mkDerivation {
           pname = "hnix";
           version = "0.4.0";
           sha256 = "0rgx97ckv5zvly6x76h7nncswfw0ik4bhnlj8n5bpl4rqzd7d4fd";
           isLibrary = true;
           isExecutable = true;
           libraryHaskellDepends = [
             ansi-wl-pprint base containers data-fix deepseq deriving-compat
             parsers regex-tdfa regex-tdfa-text semigroups text transformers
             trifecta unordered-containers
           ];
           executableHaskellDepends = [
             ansi-wl-pprint base containers data-fix deepseq
           ];
           testHaskellDepends = [
             base containers data-fix tasty tasty-hunit tasty-th text
           ];
           benchmarkHaskellDepends = [ base containers criterion text ];
           homepage = "http://github.com/jwiegley/hnix";
           description = "Haskell implementation of the Nix language";
           license = super.stdenv.lib.licenses.bsd3;
           hydraPlatforms = super.stdenv.lib.platforms.none;
         }) {};
    };
  };

  nix-path = self.haskellPackages.callPackage (
    super.fetchFromGitHub {
      owner = "imsl";
      repo = "nix-path";
      rev = "67c955dafbecf7af311e0d3bc72a8ca03db70270";
      sha256 ="1akamqxfiqhg7fr01y62pz3211ycz6lcyz0y5z9qjdn53y10nzag";
    }
  ) {
    pipes-concurrency =
      if builtins.hasAttr "pipes-concurrency_2_0_8" self.haskellPackages then
        self.haskellPackages.pipes-concurrency_2_0_8
      else
        self.haskellPackages.pipes-concurrency;
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
