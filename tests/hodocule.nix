{ lib, hodix }:
let
  inherit (hodix.lib) mkHodon card cardText;

  # The framing is all the type checks, so the body is filler.
  certificate = name: ''
    -----BEGIN CERTIFICATE-----
    ${name}
    -----END CERTIFICATE-----
  '';
  key = letter: lib.concatStrings (lib.replicate 43 letter) + "=";

  home = {
    imports = [ ./proton.nix ];
    hodon = {
      rootCertificate = certificate "proton";
      wireguard = {
        publicKey = key "p";
        endpoint = "proton.example.net:51820";
      };
      users.ada = {
        fullName = "Ada Lovelace";
        groups = [
          "family"
          "nextcloud-users"
        ];
      };
      groups = {
        nextcloud-users = { };
        family.exported = true;
      };
    };
  };
  heartwood.hodon.hodocule.peers.heartwood = {
    rootCertificate = certificate "heartwood";
    wireguard.publicKey = key "h";
    groups = [ "family" ];
  };

  hodonOf =
    extra:
    (mkHodon {
      modules = [
        home
        extra
      ];
    }).hodon;
  failuresOf =
    extra:
    (lib.evalModules {
      modules = [
        hodix.agnosticModules.hodocule
        home
        extra
      ];
    }).config.hodix.facts.failures;
  fails = needle: extra: lib.any (lib.hasInfix needle) (failuresOf extra);
  rejects = value: !(builtins.tryEval (builtins.deepSeq value value)).success;

  hodon = hodonOf heartwood;
in
{
  testPeerDomain = {
    expr = hodon.hodocule.peers.heartwood.domain;
    expected = "heartwood.hodon.internal";
  };
  testDomainsListHomeFirst = {
    expr = hodon.hodocule.domains;
    expected = [
      "proton.hodon.internal"
      "heartwood.hodon.internal"
    ];
  };
  testNoPeersIsValid = {
    expr = (hodonOf { }).hodocule.domains;
    expected = [ "proton.hodon.internal" ];
  };
  testGoodHodoculeHasNoFailures = {
    expr = failuresOf heartwood;
    expected = [ ];
  };
  testFactsStayPureData = {
    expr = builtins.fromJSON (builtins.toJSON hodon) == hodon;
    expected = true;
  };

  testCardCarriesExportedGroupsOnly = {
    expr = card hodon;
    expected.hodon.hodocule.peers.proton = {
      rootCertificate = certificate "proton";
      wireguard = {
        publicKey = key "p";
        endpoint = "proton.example.net:51820";
      };
      groups = [ "family" ];
    };
  };
  testCardTextIsAModule = {
    expr =
      (lib.evalModules {
        modules = [
          hodix.agnosticModules.hodocule
          { hodon.name = "heartwood"; }
          (import (builtins.toFile "card.nix" (cardText hodon)))
        ];
      }).config.hodon.hodocule.peers.proton.groups;
    expected = [ "family" ];
  };
  testCardNeedsARoot = {
    expr = rejects (
      card (hodonOf {
        hodon.rootCertificate = lib.mkForce null;
      })
    );
    expected = true;
  };

  testPeerNamedLikeHomeFails = {
    expr = fails "has the hodon's own name" {
      hodon.hodocule.peers.proton = heartwood.hodon.hodocule.peers.heartwood;
    };
    expected = true;
  };
  testPeerNameMustBeALabel = {
    expr = fails "not a lower-case DNS label" {
      hodon.hodocule.peers.Heartwood = heartwood.hodon.hodocule.peers.heartwood;
    };
    expected = true;
  };
  testExportedGroupKeepsItsMembers = {
    expr = hodon.groups.family.members;
    expected = [ "ada" ];
  };
  testBothEndpointsNullFails = {
    expr = fails "both null" {
      imports = [ heartwood ];
      hodon.wireguard.endpoint = lib.mkForce null;
    };
    expected = true;
  };
  testOnePeerEndpointSuffices = {
    expr = failuresOf {
      imports = [ heartwood ];
      hodon.wireguard.endpoint = lib.mkForce null;
      hodon.hodocule.peers.heartwood.wireguard.endpoint =
        "heartwood.example.net:51820";
    };
    expected = [ ];
  };

  testBadKeyRejected = {
    expr = rejects (hodonOf {
      imports = [ heartwood ];
      hodon.hodocule.peers.heartwood.wireguard.publicKey =
        lib.mkForce
          "not a key";
    });
    expected = true;
  };
  testBadEndpointRejected = {
    expr = rejects (hodonOf {
      imports = [ heartwood ];
      hodon.hodocule.peers.heartwood.wireguard.endpoint = "no port";
    });
    expected = true;
  };
  testTwoCertificatesRejected = {
    expr = rejects (hodonOf {
      imports = [ heartwood ];
      hodon.hodocule.peers.heartwood.rootCertificate = lib.mkForce (
        certificate "one" + certificate "two"
      );
    });
    expected = true;
  };
  testUnframedCertificateRejected = {
    expr = rejects (hodonOf {
      imports = [ heartwood ];
      hodon.hodocule.peers.heartwood.rootCertificate = lib.mkForce "MIIB";
    });
    expected = true;
  };
}
