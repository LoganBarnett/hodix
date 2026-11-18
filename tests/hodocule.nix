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
    imports = [ ./home.nix ];
    hodon = {
      rootCertificate = certificate "home";
      wireguard = {
        publicKey = key "p";
        endpoint = "home.example.net:51820";
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
  school.hodon.hodocule.peers.school = {
    rootCertificate = certificate "school";
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
        ../agnostic-modules/hodocule.nix
        home
        extra
      ];
    }).config.hodix.facts.failures;
  fails = needle: extra: lib.any (lib.hasInfix needle) (failuresOf extra);
  rejects = value: !(builtins.tryEval (builtins.deepSeq value value)).success;

  hodon = hodonOf school;
in
{
  testPeerDomain = {
    expr = hodon.hodocule.peers.school.domain;
    expected = "school.hodon.internal";
  };
  testDomainsListHomeFirst = {
    expr = hodon.hodocule.domains;
    expected = [
      "home.hodon.internal"
      "school.hodon.internal"
    ];
  };
  testNoPeersIsValid = {
    expr = (hodonOf { }).hodocule.domains;
    expected = [ "home.hodon.internal" ];
  };
  testGoodHodoculeHasNoFailures = {
    expr = failuresOf school;
    expected = [ ];
  };
  testFactsStayPureData = {
    expr = builtins.fromJSON (builtins.toJSON hodon) == hodon;
    expected = true;
  };

  testCardCarriesExportedGroupsOnly = {
    expr = card hodon;
    expected.hodon.hodocule.peers.home = {
      rootCertificate = certificate "home";
      wireguard = {
        publicKey = key "p";
        endpoint = "home.example.net:51820";
      };
      groups = [ "family" ];
    };
  };
  testCardTextIsAModule = {
    expr =
      (lib.evalModules {
        modules = [
          ../agnostic-modules/hodocule.nix
          { hodon.name = "school"; }
          (import (builtins.toFile "card.nix" (cardText hodon)))
        ];
      }).config.hodon.hodocule.peers.home.groups;
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
      hodon.hodocule.peers.home = school.hodon.hodocule.peers.school;
    };
    expected = true;
  };
  testPeerNameMustBeALabel = {
    expr = fails "not a lower-case DNS label" {
      hodon.hodocule.peers.School = school.hodon.hodocule.peers.school;
    };
    expected = true;
  };
  testExportedGroupKeepsItsMembers = {
    expr = hodon.groups.family.members;
    expected = [ "ada" ];
  };
  testBothEndpointsNullFails = {
    expr = fails "both null" {
      imports = [ school ];
      hodon.wireguard.endpoint = lib.mkForce null;
    };
    expected = true;
  };
  testOnePeerEndpointSuffices = {
    expr = failuresOf {
      imports = [ school ];
      hodon.wireguard.endpoint = lib.mkForce null;
      hodon.hodocule.peers.school.wireguard.endpoint =
        "school.example.net:51820";
    };
    expected = [ ];
  };

  testBadKeyRejected = {
    expr = rejects (hodonOf {
      imports = [ school ];
      hodon.hodocule.peers.school.wireguard.publicKey = lib.mkForce "not a key";
    });
    expected = true;
  };
  testBadEndpointRejected = {
    expr = rejects (hodonOf {
      imports = [ school ];
      hodon.hodocule.peers.school.wireguard.endpoint = "no port";
    });
    expected = true;
  };
  testTwoCertificatesRejected = {
    expr = rejects (hodonOf {
      imports = [ school ];
      hodon.hodocule.peers.school.rootCertificate = lib.mkForce (
        certificate "one" + certificate "two"
      );
    });
    expected = true;
  };
  testUnframedCertificateRejected = {
    expr = rejects (hodonOf {
      imports = [ school ];
      hodon.hodocule.peers.school.rootCertificate = lib.mkForce "MIIB";
    });
    expected = true;
  };
}
