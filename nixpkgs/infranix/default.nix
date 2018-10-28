{ runCommand, makeWrapper, nix-path, bashInteractive }:

runCommand "infranix" {
  buildInputs = [ makeWrapper ];
  src = ./infranix.sh;
} ''
  mkdir -p $out/bin
  ln -s "$src" $out/bin/infranix
  wrapProgram $out/bin/infranix --prefix PATH : ${nix-path}/bin:${bashInteractive}/bin
''
