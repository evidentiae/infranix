{ runCommand, makeWrapper, bashInteractive }:

runCommand "infranix" {
  buildInputs = [ makeWrapper ];
  src = ./infranix.sh;
  EVAL = ../../lib/eval-paths-module.nix;
} ''
  mkdir -p $out/bin
  ln -s "$src" $out/bin/infranix
  wrapProgram $out/bin/infranix \
    --set EVAL "$EVAL" \
    --prefix PATH : ${bashInteractive}/bin
''
