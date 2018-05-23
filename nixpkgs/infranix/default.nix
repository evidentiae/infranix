{ runCommand, makeWrapper, nix-path, bash }:

runCommand "infranix" {
  buildInputs = [ makeWrapper ];
  src = ./infranix.sh;
  propagatedBuildInputs = [ bash ];
} ''
  mkdir -p $out/bin
  ln -s "$src" $out/bin/infranix
  wrapProgram $out/bin/infranix --prefix PATH : ${nix-path}/bin
''
