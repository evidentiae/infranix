with builtins;

rec {

  pow2 = n:
    if n == 0 then 1
    else 2 * pow2 (n - 1);

  odd = n: let m = n / 2; in n != 2*m;

  mod = m: n: m - (n * (m / n));

  random = seedString: n:
    let m = binaryToInt(
      replaceStrings
        ["0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "a" "b" "c" "d" "e" "f"]
        ["0" "0" "0" "0" "0" "0" "0" "0" "1" "1" "1" "1" "1" "1" "1" "1"]
        (hashString "md5" seedString)
    ); in mod m n;

  # Encode an integer as its binary representation
  intToBinary = n:
    if n == 0 then "0"
    else if n == 1 then "1"
    else intToBinary (n / 2) + (if odd n then "1" else "0");

  # Decode the binary representation of an integer
  binaryToInt =
    let
      go = n: acc: s:
        if s == "" then acc
        else
          let
            s' = substring 0 (stringLength s - 1) s;
            d = { "0" = 0; "1" = 1; }.${substring (stringLength s - 1) 1 s};
          in go (n+1) (acc + d * pow2 n) s';
    in go 0 0;

}
