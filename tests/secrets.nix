{
  lib,
  nix-darwin,
  nixpkgs,
  hodix,
}:
let
  proton = hodix.lib.mkHodon { modules = [ ./proton.nix ]; };
  settings.hodix.secrets = {
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
      modules = [
        hodix.nixosModules.host
        hodix.nixosModules.secrets
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
        hodix.darwinModules.secrets
        (proton.forHost "scandium")
        settings
        extra
      ];
    }).config;
  silicon = nixos { };
  scandium = darwin { };
  failedAssertions =
    configuration:
    map (entry: entry.message) (
      lib.filter (entry: !entry.assertion) configuration.assertions
    );
  # A host with no key, holding one secret.
  keyless = {
    hodon.hosts.silicon.sshHostKey = lib.mkForce null;
    age.secrets.example = { };
  };
in
{
  testRekeyedSecretsAreStoredPerHost = {
    expr = toString silicon.age.rekey.localStorageDir;
    expected = toString (./fixtures + "/rekeyed/silicon");
  };
  testGeneratedSecretsHaveTheirOwnDirectory = {
    expr = toString silicon.age.rekey.generatedSecretsDir;
    expected = toString (./fixtures + "/generated");
  };
  testHandWrittenSecretsSitInTheDirectory = {
    expr = toString silicon.age.rekey.secretsDir;
    expected = toString ./fixtures;
  };
  testSecretsAreStoredInTheRepository = {
    expr = silicon.age.rekey.storageMode;
    expected = "local";
  };
  testTheHostKeyIsTheRecipient = {
    expr = silicon.age.rekey.hostPubkey;
    expected = proton.hodon.hosts.silicon.sshHostKey;
  };
  testMasterIdentitiesCarryOver = {
    expr = map (identity: identity.identity) silicon.age.rekey.masterIdentities;
    expected = [ (toString ./fixtures/master.age) ];
  };
  testGeneratorsAreAvailable = {
    expr = silicon.age.generators ? tls-ca-root;
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
    expr = toString scandium.age.rekey.localStorageDir;
    expected = toString (./fixtures + "/rekeyed/scandium");
  };
  testDarwinHostKeyIsTheRecipient = {
    expr = scandium.age.rekey.hostPubkey;
    expected = proton.hodon.hosts.scandium.sshHostKey;
  };
}
