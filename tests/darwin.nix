{
  lib,
  nix-darwin,
  hodix,
}:
let
  home = hodix.lib.mkHodon { modules = [ ./home.nix ]; };
  darwin =
    extra:
    (nix-darwin.lib.darwinSystem {
      specialArgs = hodix.lib.specialArgs;
      modules = [
        hodix.darwinModules.default
        ../system-facts/host.nix
        (home.forHost "patio")
        extra
      ];
    }).config;
  patio = darwin { };
  failedAssertions =
    configuration:
    map (entry: entry.message) (
      lib.filter (entry: !entry.assertion) configuration.assertions
    );
in
{
  testHostPlatformComesFromFacts = {
    expr = patio.nixpkgs.hostPlatform.system;
    expected = "aarch64-darwin";
  };
  testFqdnMatchesFacts = {
    expr = patio.networking.fqdn;
    expected = patio.hodix.host.fqdn;
  };
  testHostNameIsOverridable = {
    expr = (darwin { networking.hostName = "sand"; }).networking.hostName;
    expected = "sand";
  };
  testFactsDefectsBecomeAssertions = {
    expr = lib.any (lib.hasInfix "claimed more than once") (
      failedAssertions (darwin {
        hodon.hosts.intruder.interfaces.main.ipv4.address = "10.10.0.9";
      })
    );
    expected = true;
  };
}
