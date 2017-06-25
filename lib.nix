with builtins;

rec {
  hexByteToInt = s:
    let v = {
      "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4; "5" = 5; "6" = 6; "7" = 7;
      "8" = 8; "9" = 9; "a" = 10; "b" = 11; "c" = 12; "d" = 13; "e" = 14; "f" = 15;
    }; in if stringLength s != 2 then throw "Invalid hex byte"
    else (16 * v.${substring 0 1 s}) + v.${substring 1 1 s};

  mkMAC = s:
    let
      hash = hashString "md5" s;
      b6 = substring 0 1 hash;
      b5 = substring 1 2 hash;
      b4 = substring 3 2 hash;
      b3 = substring 5 2 hash;
      b2 = substring 7 2 hash;
      b1 = substring 9 2 hash;
   in "${b6}2:${b5}:${b4}:${b3}:${b2}:${b1}";

  mkUUID = s:
    let
      hash = hashString "sha1" s;
      s1 = substring 0 8 hash;
      s2 = substring 8 4 hash;
      s3 = substring 12 4 hash;
      s4 = substring 16 4 hash;
      s5 = substring 20 12 hash;
    in "${s1}-${s2}-${s3}-${s4}-${s5}";

  genByte = s: n: toString (hexByteToInt (
    substring n 2 (mkMAC s)
  ));
}
