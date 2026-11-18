{
  lib,
  nix-darwin,
  nixpkgs,
  hodix,
}:
let
  home = hodix.lib.mkHodon { modules = [ ./home.nix ]; };
  # The framing is all the type checks, so the body is filler.
  certificate = name: ''
    -----BEGIN CERTIFICATE-----
    ${name}
    -----END CERTIFICATE-----
  '';
  generatedRoot = builtins.readFile ./fixtures/with-root/generated/root-ca.crt;
  settings.hodix = {
    secrets = {
      # A directory on disk, since the modules read fixed paths under it.
      directory = ./fixtures;
      masterIdentities = [
        {
          identity = ./fixtures/master.age;
          pubkey = ./fixtures/master.pub;
        }
      ];
    };
    tls.root.subject = {
      country = "US";
      state = "Oregon";
      location = "Portland";
    };
  };
  nixos =
    extra:
    (nixpkgs.lib.nixosSystem {
      specialArgs = hodix.lib.specialArgs;
      modules = [
        hodix.nixosModules.default
        ../system-facts/host.nix
        ../system-facts/secrets.nix
        ../system-facts/tls.nix
        (home.forHost "balcony")
        settings
        { system.stateVersion = "26.05"; }
        extra
      ];
    }).config;
  darwin =
    extra:
    (nix-darwin.lib.darwinSystem {
      specialArgs = hodix.lib.specialArgs;
      modules = [
        hodix.darwinModules.default
        ../system-facts/host.nix
        ../system-facts/secrets.nix
        ../system-facts/tls.nix
        (home.forHost "patio")
        settings
        extra
      ];
    }).config;
  balcony = nixos {
    hodix.tls.certificates."ldap.home.hodon.internal" = { };
  };
  ldap = balcony.hodix.tls.certificates."ldap.home.hodon.internal";
  ldapKey = balcony.age.secrets.${ldap.keySecret};
  withRoot.hodix.secrets.directory = lib.mkForce ./fixtures/with-root;
  failedAssertions =
    configuration:
    map (entry: entry.message) (
      lib.filter (entry: !entry.assertion) configuration.assertions
    );
in
{
  # A bridge answers for a federated hodon under this root, so the constraint
  # is wider than the hodon's own domain.
  testTheRootSignsForEveryHodon = {
    expr = balcony.age.secrets.root-ca.settings.tls.domain;
    expected = "hodon.internal";
  };
  testTheRootKeyStaysInTheRepository = {
    expr = balcony.age.secrets.root-ca.intermediary;
    expected = true;
  };
  testTheOrganizationDefaultsToTheHodon = {
    expr = balcony.age.secrets.root-ca.settings.tls.subject.organization;
    expected = "home";
  };
  testRootSettingsPassThroughUntouched = {
    expr =
      (nixos { hodix.tls.root.common-name = "home root"; })
      .age.secrets.root-ca.settings.tls.common-name;
    expected = "home root";
  };
  testTheSubjectSpeaksTheGeneratorsNames = {
    expr = lib.attrNames balcony.age.secrets.root-ca.settings.tls.subject;
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
    expected = "ldap.home.hodon.internal";
  };
  testValidityIsLeftToTheGeneratorByDefault = {
    expr = ldapKey.settings ? validity;
    expected = false;
  };
  testTheHodonSetsValidityForEveryCertificate = {
    expr =
      (nixos {
        hodix.tls.certificateValidityDays = 90;
        hodix.tls.certificates."ldap.home.hodon.internal" = { };
      }).age.secrets."tls-ldap.home.hodon.internal.key".settings.validity;
    expected = 90;
  };
  testACertificateSetsItsOwnValidity = {
    expr =
      (nixos {
        hodix.tls.certificateValidityDays = 90;
        hodix.tls.certificates."ldap.home.hodon.internal".validityDays = 30;
      }).age.secrets."tls-ldap.home.hodon.internal.key".settings.validity;
    expected = 30;
  };
  testTheKeyIsASecretOfTheHost = {
    expr = ldap.keyFile;
    expected = ldapKey.path;
  };
  testTheCertificateSitsBesideTheKey = {
    expr = toString ldap.certificateFile;
    expected = toString (
      ./fixtures + "/generated/tls-ldap.home.hodon.internal.crt"
    );
  };
  testANameOutsideHodonInternalIsRejected = {
    expr = lib.any (lib.hasInfix "not under hodon.internal") (
      failedAssertions (nixos {
        hodix.tls.certificates."ldap.example.com" = { };
      })
    );
    expected = true;
  };
  testAFederatedHodonsNameIsAccepted = {
    expr = lib.any (lib.hasInfix "not under") (
      failedAssertions (nixos {
        hodix.tls.certificates."nextcloud.school.hodon.internal" = { };
      })
    );
    expected = false;
  };
  testNothingIsTrustedBeforeTheRootExists = {
    expr = balcony.security.pki.certificates;
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
          ./home.nix
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
