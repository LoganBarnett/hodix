{
  lib,
  nixpkgs,
  hodix,
}:
let
  home = hodix.lib.mkHodon { modules = [ ./home.nix ]; };
  nixos =
    extra:
    (nixpkgs.lib.nixosSystem {
      specialArgs = hodix.lib.specialArgs;
      modules = [
        hodix.nixosModules.default
        ../system-facts/host.nix
        (home.forHost "balcony")
        { system.stateVersion = "26.05"; }
        extra
      ];
    }).config;
  balcony = nixos { };
  failedAssertions =
    configuration:
    map (entry: entry.message) (
      lib.filter (entry: !entry.assertion) configuration.assertions
    );
  rejects = value: !(builtins.tryEval (builtins.deepSeq value value)).success;
in
{
  # The modules read hodix's inputs from the special arguments, and a host
  # built without them is told so rather than left in an infinite recursion.
  testAHandBuiltHostNeedsTheSpecialArgs = {
    expr =
      rejects
        (nixpkgs.lib.nixosSystem {
          modules = [
            hodix.nixosModules.default
            hodix.nixosFacts.default
            (home.forHost "balcony")
          ];
        }).config.networking.hostName;
    expected = true;
  };
  testHostPlatformComesFromFacts = {
    expr = balcony.nixpkgs.hostPlatform.system;
    expected = "x86_64-linux";
  };
  testFqdnMatchesFacts = {
    expr = balcony.networking.fqdn;
    expected = balcony.hodix.host.fqdn;
  };
  testHostNameIsOverridable = {
    expr = (nixos { networking.hostName = "sand"; }).networking.hostName;
    expected = "sand";
  };
  testFactsDefectsBecomeAssertions = {
    expr = lib.any (lib.hasInfix "claimed more than once") (
      failedAssertions (nixos {
        hodon.hosts.intruder.interfaces.main.ipv4.address = "10.10.0.9";
      })
    );
    expected = true;
  };
}
