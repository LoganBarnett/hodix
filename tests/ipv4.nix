{ lib }:
let
  ipv4 = import ../lib/ipv4.nix { inherit lib; };
  main = ipv4.parseCidr "10.10.0.0/24";
in
{
  testToInt = {
    expr = ipv4.toInt "10.10.0.9";
    expected = 168427529;
  };
  testParseCidr = {
    expr = main;
    expected = {
      address = "10.10.0.0";
      base = 168427520;
      prefixLength = 24;
      size = 256;
    };
  };
  testParseCidrWholeSpace = {
    expr = (ipv4.parseCidr "0.0.0.0/0").size;
    expected = 4294967296;
  };
  testParseCidrRejectsHostBits = {
    expr = ipv4.parseCidr "10.10.0.1/24";
    expected = null;
  };
  testParseCidrRejectsLongPrefix = {
    expr = ipv4.parseCidr "10.10.0.0/33";
    expected = null;
  };
  testParseCidrRejectsLargeOctet = {
    expr = ipv4.parseCidr "10.10.256.0/24";
    expected = null;
  };
  testParseCidrRejectsLeadingZero = {
    expr = ipv4.parseCidr "10.10.00.0/24";
    expected = null;
  };
  testParseCidrRejectsBareAddress = {
    expr = ipv4.parseCidr "10.10.0.0";
    expected = null;
  };
  testNestedNetworksOverlap = {
    expr = ipv4.overlaps (ipv4.parseCidr "10.10.0.0/16") main;
    expected = true;
  };
  testNeighbouringNetworksDoNotOverlap = {
    expr = ipv4.overlaps (ipv4.parseCidr "10.10.1.0/24") main;
    expected = false;
  };
  testHostAddress = {
    expr = ipv4.isHostAddress main "10.10.0.9";
    expected = true;
  };
  testNetworkAddressIsNotAHost = {
    expr = ipv4.isHostAddress main "10.10.0.0";
    expected = false;
  };
  testBroadcastAddressIsNotAHost = {
    expr = ipv4.isHostAddress main "10.10.0.255";
    expected = false;
  };
  testOutsideAddressIsNotAHost = {
    expr = ipv4.isHostAddress main "10.10.1.9";
    expected = false;
  };
  testPointToPointNetworkUsesBothAddresses = {
    expr = map (ipv4.isHostAddress (ipv4.parseCidr "10.10.0.0/31")) [
      "10.10.0.0"
      "10.10.0.1"
    ];
    expected = [
      true
      true
    ];
  };
}
