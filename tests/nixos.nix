{
  lib,
  nixpkgs,
  hodix,
}:
let
  proton = hodix.lib.mkHodon { modules = [ ./proton.nix ]; };
  nixos =
    extra:
    (nixpkgs.lib.nixosSystem {
      modules = [
        hodix.nixosModules.host
        (proton.forHost "silicon")
        { system.stateVersion = "26.05"; }
        extra
      ];
    }).config;
  silicon = nixos { };
  failedAssertions =
    configuration:
    map (entry: entry.message) (
      lib.filter (entry: !entry.assertion) configuration.assertions
    );
in
{
  testHostPlatformComesFromFacts = {
    expr = silicon.nixpkgs.hostPlatform.system;
    expected = "x86_64-linux";
  };
  testFqdnMatchesFacts = {
    expr = silicon.networking.fqdn;
    expected = silicon.hodix.host.fqdn;
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
