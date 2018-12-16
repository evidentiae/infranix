{ runCommand, makeWrapper, bashInteractive }:

runCommand "infranix" {
  buildInputs = [ makeWrapper ];
  src = ./infranix.sh;
  INFRANIX_LIB = ../../lib;
} ''
  mkdir -p $out/bin
  ln -s "$src" $out/bin/infranix
  wrapProgram $out/bin/infranix \
    --set INFRANIX_LIB "$INFRANIX_LIB" \
    --prefix PATH : ${bashInteractive}/bin
''
