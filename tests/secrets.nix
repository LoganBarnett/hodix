{
  lib,
  nix-darwin,
  nixpkgs,
  hodix,
}:
let
  home = hodix.lib.mkHodon { modules = [ ./home.nix ]; };
  settings.hodix.secrets = {
    # A directory on disk, since the modules read fixed paths under it.
    directory = ./fixtures;
    masterIdentities = [
      {
        identity = ./fixtures/master.age;
        pubkey = ./fixtures/master.pub;
      }
    ];
  };
  nixos =
    extra:
    (nixpkgs.lib.nixosSystem {
      specialArgs = hodix.lib.specialArgs;
      modules = [
        hodix.nixosModules.default
        ../system-facts/host.nix
        ../system-facts/secrets.nix
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
        (home.forHost "patio")
        settings
        extra
      ];
    }).config;
  balcony = nixos { };
  patio = darwin { };
  # A flake's `self.outPath` is a store path string with context, so the
  # fixture is one too.
  flakeRoot = "${./.}";
  # A hodon that leaves every secrets setting to its default.
  defaults =
    (nixpkgs.lib.nixosSystem {
      specialArgs = hodix.lib.specialArgs;
      modules = [
        hodix.nixosModules.default
        ../system-facts/host.nix
        ../system-facts/secrets.nix
        (
          (hodix.lib.mkHodon {
            modules = [ ./home.nix ];
            self.outPath = flakeRoot;
          }).forHost
            "balcony"
        )
        { system.stateVersion = "26.05"; }
      ];
    }).config;
  failedAssertions =
    configuration:
    map (entry: entry.message) (
      lib.filter (entry: !entry.assertion) configuration.assertions
    );
  # A host with no key, holding one secret.
  keyless = {
    hodon.hosts.balcony.sshHostKey = lib.mkForce null;
    age.secrets.example = { };
  };
in
{
  testRekeyedSecretsAreStoredPerHost = {
    expr = toString balcony.age.rekey.localStorageDir;
    expected = toString (./fixtures + "/rekeyed/balcony");
  };
  testGeneratedSecretsHaveTheirOwnDirectory = {
    expr = toString balcony.age.rekey.generatedSecretsDir;
    expected = toString (./fixtures + "/generated");
  };
  testHandWrittenSecretsAreIssued = {
    expr = toString balcony.age.rekey.secretsDir;
    expected = toString (./fixtures + "/issued");
  };
  testTheDirectoryDefaultsToSecretsUnderTheFlake = {
    expr = toString defaults.hodix.secrets.directory;
    expected = flakeRoot + "/secrets";
  };
  testTheMasterIdentityDefaultsToTheDirectory = {
    expr = map (
      identity: toString identity.identity
    ) defaults.age.rekey.masterIdentities;
    expected = [ (flakeRoot + "/secrets/master.age") ];
  };
  testAManagedHostGeneratesItsHostKey = {
    expr = {
      inherit (balcony.age.secrets."balcony-ssh-host-key") intermediary;
      script = balcony.age.secrets."balcony-ssh-host-key".generator.script;
    };
    expected = {
      intermediary = true;
      script = "ssh-ed25519-with-pub";
    };
  };
  # The fixtures hold a generated key for balcony, and this hodon states none.
  testTheHostKeyDefaultsToTheGeneratedOne = {
    expr =
      (hodix.lib.mkHodon {
        modules = [
          {
            hodon = {
              name = "home";
              defaultHost = "balcony";
              hosts.balcony.system = "x86_64-linux";
              # The host has no address, so the network services are off.
              services = {
                dhcp.enable = false;
                dns.enable = false;
              };
            };
            hodix.secrets.directory = ./fixtures/with-root;
          }
        ];
      }).hodon.hosts.balcony.sshHostKey;
    expected =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJabRtUihDjJ+AiWalAI+UwL5Wva+0jfiDui5pt7tGxb balcony-ssh-host-key";
  };
  testAnAbsentMasterPubkeyIsNull = {
    expr = map (identity: identity.pubkey) defaults.age.rekey.masterIdentities;
    expected = [ null ];
  };
  testSecretsAreStoredInTheRepository = {
    expr = balcony.age.rekey.storageMode;
    expected = "local";
  };
  testTheHostKeyIsTheRecipient = {
    expr = balcony.age.rekey.hostPubkey;
    expected = home.hodon.hosts.balcony.sshHostKey;
  };
  testMasterIdentitiesCarryOver = {
    expr = map (identity: identity.identity) balcony.age.rekey.masterIdentities;
    expected = [ (toString ./fixtures/master.age) ];
  };
  testGeneratorsAreAvailable = {
    expr = balcony.age.generators ? tls-ca-root;
    expected = true;
  };
  testAHostWithoutAKeyCannotHoldASecret = {
    expr = lib.any (lib.hasInfix "sshHostKey") (
      failedAssertions (nixos keyless)
    );
    expected = true;
  };
  testAnIntermediaryNeedsNoHostKey = {
    expr = lib.any (lib.hasInfix "sshHostKey") (
      failedAssertions (nixos {
        imports = [ keyless ];
        age.secrets.example.intermediary = true;
      })
    );
    expected = false;
  };
  testTheDirectoryIsRequired = {
    expr = lib.any (lib.hasInfix "hodix.secrets.directory") (
      failedAssertions (nixos {
        hodix.secrets.directory = lib.mkForce null;
      })
    );
    expected = true;
  };
  testDarwinRekeyedSecretsAreStoredPerHost = {
    expr = toString patio.age.rekey.localStorageDir;
    expected = toString (./fixtures + "/rekeyed/patio");
  };
  testDarwinHostKeyIsTheRecipient = {
    expr = patio.age.rekey.hostPubkey;
    expected = home.hodon.hosts.patio.sshHostKey;
  };
}
