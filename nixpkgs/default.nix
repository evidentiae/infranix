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

  nixos-multi-spawn-client = super.writeScriptBin "nixos-multi-spawn-client" ''
    #!${self.stdenv.shell}
    set -e
    set -o pipefail

    config="$1"
    net="$2"
    socat=${self.socat}/bin/socat
    socket="/run/nixos-multi-spawn/$(id -gn).socket"

    if ! [ -w "$socket" ]; then
      echo >&2 "Socket '$socket' not writable"
      exit 1
    fi

    if ! [ -r "$config" ]; then
      echo >&2 "Config '$config' not readable"
      exit 1
    fi

    if [ -z "$net" ] || ! [[ "$net" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
      echo >&2 "Invalid net '$net'"
      exit 1
    fi

    function printargs() {
      echo -e "\n$1"
      test -n "$net" && echo -e "\nNET=$net"
      echo "CONFIG=$(${self.jq}/bin/jq -cr . "$config")"
    }

    function notify_ready() {
      if [ -n "$NOTIFY_SOCKET" ]; then
        echo "READY=1" | $socat UNIX-SENDTO:$NOTIFY_SOCKET STDIO
      fi
    }

    printargs | $socat -,ignoreeof UNIX-CONNECT:"$socket" | (
      notify_ready
      while read line; do
        if [ "$line" == "DONE" ]; then
          ${self.gnutar}/bin/tar xBf -
        else
          echo "$line"
        fi
      done
    )
  '';

  nix-store-gcs-proxy = self.callPackage ((builtins.fetchTarball {
    url = https://github.com/digital-asset/daml/archive/9c7357c7dea50ccd6038d9e4404065710a823384.tar.gz;
    sha256 = "1dfwwgl4nqckzyampf267q8r5sl8w74f3wykarananngznkpwrgq";
  }) + "/nix/tools/nix-store-gcs-proxy") {};
}
