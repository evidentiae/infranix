{ runCommand, makeWrapper }:

runCommand "infranix" {
  buildInputs = [ makeWrapper ];
  src = ./infranix.sh;
} ''
  mkdir -p $out/bin
  ln -s "$src" $out/bin/infranix
  wrapProgram $out/bin/infranix --set EVAL "${./eval.nix}"
''
