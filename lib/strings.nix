with builtins;

{
  
  leftPadString = char: n: str:
    concatStringsSep "" (genList (_:char) (n - stringLength str)) + str;

}
