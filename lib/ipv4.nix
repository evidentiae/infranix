with builtins;
with import ./strings.nix;
with import ./integer.nix;

let

  ipRegex = ''^([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+)$'';

in rec {

  # nix-repl> ipOctets "10.11.12.13"
  # [ 10 11 12 13 ]
  ipToOctets = ip: map fromJSON (match ipRegex ip);

  octetsToIp = octets: concatStringsSep "." (map toString octets);

  # nix-repl> ipToBinary "10.11.12.13"
  # "00001010000010110000110000001101"
  ipToBinary = ip:
    concatStringsSep "" (map (o: leftPadString "0" 8 (intToBinary o)) (ipToOctets ip));

  binaryIpToOctets = b: map binaryToInt [
    (substring 0 8 b)
    (substring 8 8 b)
    (substring 16 8 b)
    (substring 24 8 b)
  ];

  # For the given network and prefix return the IP address for the host at the
  # given index
  ipAddressOfHost = network: prefix: hostIndex:
    let
      hostAddr = leftPadString "0" (32 - prefix) (intToBinary hostIndex);
    in octetsToIp (
      binaryIpToOctets (substring 0 prefix (ipToBinary network) + hostAddr)
    );

  # For the given prefix, return the index of the host
  indexOfHost = ipaddr: prefix: binaryToInt (
    let b = ipToBinary ipaddr;
    in substring prefix ((stringLength b) - prefix) b
  );

  # Return the host count for the given network prefix
  hostCount = prefix: pow2 (32 - prefix) - 2;

  # Return the broadcast address for the given network
  broadcastAddress = network: prefix:
    ipAddressOfHost network prefix ((hostCount prefix) + 1);

  # Return the first host IP address of a network
  minHostAddress = network: prefix: ipAddressOfHost network prefix 1;

  # Return the last host IP address of a network
  maxHostAddress = network: prefix:
    ipAddressOfHost network prefix (hostCount prefix);

  # Split a CIDR address into network and prefix
  #
  # nix-repl> splitCIDR "10.10.0.2/24"
  # { network = "10.10.0.2"; prefix = 24; }
  #
  splitCIDR = cidr: let xs = match "^([[:digit:].]+)/([[:digit:]]+)$" cidr; in {
    network = head xs;
    prefix = fromJSON (elemAt xs (length xs - 1));
  };
}
