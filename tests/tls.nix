{
  lib,
  nix-darwin,
  nixpkgs,
  hodix,
}:
let
  proton = hodix.lib.mkHodon { modules = [ ./proton.nix ]; };
  # The framing is all the type checks, so the body is filler.
  certificate = name: ''
    -----BEGIN CERTIFICATE-----
    ${name}
    -----END CERTIFICATE-----
  '';
  generatedRoot = builtins.readFile ./fixtures/with-root/generated/root-ca.crt;
  settings.hodix = {
    secrets = {
      directory = ./fixtures;
      masterIdentities = [
        {
          identity = ./fixtures/master.age;
          pubkey = ./fixtures/master.pub;
        }
      ];
    };
    tls.subject = {
      country = "US";
      state = "Oregon";
      locality = "Portland";
    };
  };
  nixos =
    extra:
    (nixpkgs.lib.nixosSystem {
      modules = [
        hodix.nixosModules.host
        hodix.nixosModules.tls
        (proton.forHost "silicon")
        settings
        { system.stateVersion = "26.05"; }
        extra
      ];
    }).config;
  darwin =
    extra:
    (nix-darwin.lib.darwinSystem {
      modules = [
        hodix.darwinModules.host
        hodix.darwinModules.tls
        (proton.forHost "scandium")
        settings
        extra
      ];
    }).config;
  silicon = nixos {
    hodix.tls.certificates."ldap.proton.hodon.internal" = { };
  };
  ldap = silicon.hodix.tls.certificates."ldap.proton.hodon.internal";
  ldapKey = silicon.age.secrets.${ldap.keySecret};
  withRoot.hodix.secrets.directory = lib.mkForce ./fixtures/with-root;
  failedAssertions =
    configuration:
    map (entry: entry.message) (
      lib.filter (entry: !entry.assertion) configuration.assertions
    );
in
{
  testTheRootIsConstrainedToTheDomain = {
    expr = silicon.age.secrets.root-ca.settings.tls.domain;
    expected = "proton.hodon.internal";
  };
  testTheRootKeyStaysInTheRepository = {
    expr = silicon.age.secrets.root-ca.intermediary;
    expected = true;
  };
  testTheOrganizationDefaultsToTheHodon = {
    expr = silicon.age.secrets.root-ca.settings.tls.subject.organization;
    expected = "proton";
  };
  testTheSubjectSpeaksTheGeneratorsNames = {
    expr = lib.attrNames silicon.age.secrets.root-ca.settings.tls.subject;
    expected = [
      "country"
      "location"
      "organization"
      "organizational-unit"
      "state"
    ];
  };
  testACertificateIsSignedByTheRoot = {
    expr = (lib.head ldapKey.generator.dependencies).id;
    expected = "root-ca";
  };
  testACertificateIsIssuedForItsName = {
    expr = ldapKey.settings.fqdn;
    expected = "ldap.proton.hodon.internal";
  };
  testValidityIsLeftToTheGeneratorByDefault = {
    expr = ldapKey.settings ? validity;
    expected = false;
  };
  testTheHodonSetsValidityForEveryCertificate = {
    expr =
      (nixos {
        hodix.tls.certificateValidityDays = 90;
        hodix.tls.certificates."ldap.proton.hodon.internal" = { };
      }).age.secrets."tls-ldap.proton.hodon.internal.key".settings.validity;
    expected = 90;
  };
  testACertificateSetsItsOwnValidity = {
    expr =
      (nixos {
        hodix.tls.certificateValidityDays = 90;
        hodix.tls.certificates."ldap.proton.hodon.internal".validityDays = 30;
      }).age.secrets."tls-ldap.proton.hodon.internal.key".settings.validity;
    expected = 30;
  };
  testTheKeyIsASecretOfTheHost = {
    expr = ldap.keyFile;
    expected = ldapKey.path;
  };
  testTheCertificateSitsBesideTheKey = {
    expr = toString ldap.certificateFile;
    expected = toString (
      ./fixtures + "/generated/tls-ldap.proton.hodon.internal.crt"
    );
  };
  testANameOutsideTheDomainIsRejected = {
    expr = lib.any (lib.hasInfix "not under proton.hodon.internal") (
      failedAssertions (nixos {
        hodix.tls.certificates."ldap.example.com" = { };
      })
    );
    expected = true;
  };
  testImportingSecretsBesideTlsIsFine = {
    expr =
      (nixos { imports = [ hodix.nixosModules.secrets ]; })
      .age.rekey.storageMode;
    expected = "local";
  };
  testNothingIsTrustedBeforeTheRootExists = {
    expr = silicon.security.pki.certificates;
    expected = [ ];
  };
  testTheRootIsTrustedOnceItExists = {
    expr = (nixos withRoot).security.pki.certificates;
    expected = [ generatedRoot ];
  };
  testTheGeneratedRootBecomesTheFact = {
    expr =
      (hodix.lib.mkHodon {
        modules = [
          ./proton.nix
          withRoot
        ];
      }).hodon.rootCertificate;
    expected = generatedRoot;
  };
  testAnExplicitRootWins = {
    expr =
      (nixos {
        imports = [ withRoot ];
        hodon.rootCertificate = certificate "elsewhere";
      }).hodon.rootCertificate;
    expected = certificate "elsewhere";
  };
  testDarwinTrustsTheRoot = {
    expr = (darwin withRoot).security.pki.certificates;
    expected = [ generatedRoot ];
  };
}
