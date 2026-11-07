# This is the IPv4 arithmetic that validates hodon facts.  The nixpkgs
# lib.network set covers IPv6 only.
{ lib }:
let
  # Leading zeros are excluded because lib.toInt rejects them as ambiguous.
  octet = "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])";
  addressPattern = "${octet}(\\.${octet}){3}";
  pow2 = n: if n == 0 then 1 else 2 * pow2 (n - 1);
in
rec {
  isAddress = address: builtins.match addressPattern address != null;

  toInt =
    address:
    lib.foldl (acc: part: acc * 256 + lib.toInt part) 0 (
      lib.splitString "." address
    );

  # Null means the string is not a network in CIDR notation.  A network with
  # host bits set is rejected so that each network has one spelling.
  parseCidr =
    cidr:
    let
      parts = builtins.match "(${addressPattern})/(3[0-2]|[12]?[0-9])" cidr;
      base = toInt (lib.head parts);
      prefixLength = lib.toInt (lib.last parts);
      size = pow2 (32 - prefixLength);
    in
    if parts == null || lib.mod base size != 0 then
      null
    else
      {
        inherit base prefixLength size;
        address = lib.head parts;
      };

  overlaps = a: b: a.base < b.base + b.size && b.base < a.base + a.size;

  # The first and last addresses of a network are the network and broadcast
  # addresses.  Networks of two addresses or fewer have neither.
  isHostAddress =
    network: address:
    let
      number = toInt address;
      last = network.base + network.size - 1;
    in
    network.base <= number
    && number <= last
    && (network.size <= 2 || (number != network.base && number != last));
}
