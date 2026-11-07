{
  lib,
  nix-darwin,
  hodix,
}:
let
  proton = hodix.lib.mkHodon { modules = [ ./proton.nix ]; };
  darwin =
    extra:
    (nix-darwin.lib.darwinSystem {
      modules = [
        hodix.darwinModules.host
        (proton.forHost "scandium")
        extra
      ];
    }).config;
  scandium = darwin { };
  failedAssertions =
    configuration:
    map (entry: entry.message) (
      lib.filter (entry: !entry.assertion) configuration.assertions
    );
in
{
  testHostPlatformComesFromFacts = {
    expr = scandium.nixpkgs.hostPlatform.system;
    expected = "aarch64-darwin";
  };
  testFqdnMatchesFacts = {
    expr = scandium.networking.fqdn;
    expected = scandium.hodix.host.fqdn;
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
