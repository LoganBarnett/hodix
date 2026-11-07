{ lib, hodix }:
let
  inherit (hodix.lib) mkHodon;
  inherit (hodix.agnosticProfiles)
    hostname-convention-bean
    hostname-convention-periodic-table
    hostname-convention-petal
    hostname-convention-wood
    ;

  good = ./proton.nix;
  duplicateAddress.hodon.hosts.intruder.interfaces.main.ipv4.address =
    "10.10.0.9";

  hodonOf =
    extra:
    (mkHodon {
      modules = [
        good
        extra
      ];
    }).hodon;
  failuresOf =
    extra:
    (lib.evalModules {
      modules = [
        hodix.agnosticModules.facts
        good
        extra
      ];
    }).config.hodix.facts.failures;
  fails = needle: extra: lib.any (lib.hasInfix needle) (failuresOf extra);
  rejects = value: !(builtins.tryEval (builtins.deepSeq value value)).success;
  bare = module: (mkHodon { modules = [ module ]; }).hodon;
  hostnamesWith = convention: (hodonOf { imports = [ convention ]; }).hostnames;
  shorterOrEarlier =
    a: b:
    lib.stringLength a < lib.stringLength b
    || (lib.stringLength a == lib.stringLength b && a < b);

  # Stands in for the assertions option that NixOS, nix-darwin, and
  # home-manager each declare.
  assertionsStub.options.assertions = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    default = [ ];
  };
  inHost =
    extra:
    (lib.evalModules {
      class = "nixos";
      modules = [
        (mkHodon {
          modules = [
            good
            extra
          ];
        }).module
        assertionsStub
      ];
    }).config;

  asHost =
    name:
    (lib.evalModules {
      modules = [ ((mkHodon { modules = [ good ]; }).forHost name) ];
    }).config.hodix.host;

  hodon = hodonOf { };
in
{
  testForHostSeesItsOwnFacts = {
    expr = (asHost "silicon").fqdn;
    expected = "silicon.proton.hodon.internal";
  };
  testUnknownHostNameRejected = {
    expr = rejects (asHost "nope");
    expected = true;
  };
  testDomain = {
    expr = hodon.domain;
    expected = "proton.hodon.internal";
  };
  testHostName = {
    expr = hodon.hosts.silicon.name;
    expected = "silicon";
  };
  testFqdn = {
    expr = hodon.hosts.silicon.fqdn;
    expected = "silicon.proton.hodon.internal";
  };
  testPrimaryAddress = {
    expr = hodon.hosts.silicon.ipv4.address;
    expected = "10.10.0.9";
  };
  testOnlyInterfaceIsPrimary = {
    expr = hodon.hosts.scandium.ipv4.address;
    expected = "10.10.0.20";
  };
  testDynamicAddressIsNull = {
    expr = hodon.hosts.printer.ipv4.address;
    expected = null;
  };
  testInterfaceNetworkDefaultsToItsName = {
    expr = hodon.hosts.silicon.interfaces.vpn.network;
    expected = "vpn";
  };
  testNetworkDerivedValues = {
    expr = {
      inherit (hodon.networks.main.ipv4) address prefixLength;
    };
    expected = {
      address = "10.10.0.0";
      prefixLength = 24;
    };
  };
  testGoodFactsHaveNoFailures = {
    expr = failuresOf { };
    expected = [ ];
  };
  testFactsArePureData = {
    expr = builtins.fromJSON (builtins.toJSON hodon) == hodon;
    expected = true;
  };

  testAvailableHostnamesKeepPoolOrder = {
    expr =
      (hodonOf {
        hodon.hostnames.pool = [
          "silicon"
          "pine"
          "scandium"
          "cedar"
        ];
      }).hostnames.available;
    expected = [
      "pine"
      "cedar"
    ];
  };
  testPeriodicTableConvention = {
    expr =
      let
        hostnames = hostnamesWith hostname-convention-periodic-table;
      in
      {
        inherit (hostnames) convention;
        pool = lib.length hostnames.pool;
        available = lib.length hostnames.available;
        next = lib.head hostnames.available;
      };
    expected = {
      convention = "periodic-table";
      pool = 118;
      available = 116;
      next = "hydrogen";
    };
  };
  testWoodConvention = {
    expr = lib.take 4 (hostnamesWith hostname-convention-wood).available;
    expected = [
      "ash"
      "elm"
      "fir"
      "koa"
    ];
  };
  testPetalConvention = {
    expr = lib.take 4 (hostnamesWith hostname-convention-petal).available;
    expected = [
      "iris"
      "lily"
      "rose"
      "aster"
    ];
  };
  testBeanConvention = {
    expr = lib.take 4 (hostnamesWith hostname-convention-bean).available;
    expected = [
      "red"
      "soy"
      "wax"
      "fava"
    ];
  };
  # The periodic table follows atomic number.  Every other pool is shortest
  # first and then alphabetical.
  testPoolOrder = {
    expr =
      lib.all
        (
          profile:
          (hostnamesWith profile).pool
          == lib.sort shorterOrEarlier (hostnamesWith profile).pool
        )
        [
          hostname-convention-bean
          hostname-convention-petal
          hostname-convention-wood
        ];
    expected = true;
  };
  testTwoConventionsRejected = {
    expr = rejects (hodonOf {
      imports = [
        hostname-convention-periodic-table
        hostname-convention-wood
      ];
    });
    expected = true;
  };

  testHostSeesTheSameFacts = {
    expr = (inHost { }).hodon == hodon;
    expected = true;
  };
  testHostAssertionsEmptyForGoodFacts = {
    expr = (inHost { }).assertions;
    expected = [ ];
  };
  testHostAssertionsCarryFailures = {
    expr = map (entry: entry.assertion) (inHost duplicateAddress).assertions;
    expected = [ false ];
  };

  testMissingNameRejected = {
    expr = rejects (bare { });
    expected = true;
  };
  testUpperCaseNameRejected = {
    expr = rejects (bare {
      hodon.name = "Proton";
    });
    expected = true;
  };
  testDomainIsReadOnly = {
    expr = rejects (hodonOf {
      hodon.domain = "proton";
    });
    expected = true;
  };
  testUpperCaseMacRejected = {
    expr = rejects (hodonOf {
      hodon.hosts.printer.interfaces.main = {
        macAddresses = [ "AC:19:8E:F6:04:A1" ];
      };
    });
    expected = true;
  };
  testMalformedAddressRejected = {
    expr = rejects (hodonOf {
      hodon.hosts.printer.interfaces.main.ipv4.address = "10.10.0.256";
    });
    expected = true;
  };
  testCidrWithHostBitsRejected = {
    expr = rejects (hodonOf {
      hodon.networks.iot.ipv4.cidr = "10.20.0.1/24";
    });
    expected = true;
  };
  testUnknownSystemRejected = {
    expr = rejects (hodonOf {
      hodon.hosts.printer.system = "aarch64-ios";
    });
    expected = true;
  };
  testAnyKnownSystemAccepted = {
    expr =
      (hodonOf { hodon.hosts.printer.system = "x86_64-freebsd"; })
      .hosts.printer.system;
    expected = "x86_64-freebsd";
  };
  testUnknownHostKeyRejected = {
    expr = rejects (hodonOf {
      hodon.hosts.printer.mac = "ac:19:8e:f6:04:a0";
    });
    expected = true;
  };
  testMkHodonRejectsFailures = {
    expr = rejects (hodonOf duplicateAddress);
    expected = true;
  };

  testUnknownNetworkFails = {
    expr = fails "which is not in hodon.networks" {
      hodon.hosts.printer.interfaces.lab = { };
    };
    expected = true;
  };
  testAddressOutsideNetworkFails = {
    expr = fails "10.20.0.5, which is not a host address in 10.10.0.0/24" {
      hodon.hosts.printer.interfaces.main.ipv4.address = "10.20.0.5";
    };
    expected = true;
  };
  testNetworkAddressFails = {
    expr = fails "not a host address" {
      hodon.hosts.printer.interfaces.main.ipv4.address = "10.10.0.0";
    };
    expected = true;
  };
  testBroadcastAddressFails = {
    expr = fails "not a host address" {
      hodon.hosts.printer.interfaces.main.ipv4.address = "10.10.0.255";
    };
    expected = true;
  };
  testDuplicateAddressFails = {
    expr = fails "Address 10.10.0.9 is claimed more than once" duplicateAddress;
    expected = true;
  };
  testMacOnTwoHostsFails = {
    expr = fails "claimed by more than one host" {
      hodon.hosts.intruder.interfaces.main.macAddresses = [
        "b8:ca:3a:77:a9:2a"
      ];
    };
    expected = true;
  };
  testMacOnTwoInterfacesOfOneHostPasses = {
    expr = failuresOf {
      hodon.hosts.silicon.interfaces.vpn.macAddresses = [ "b8:ca:3a:77:a9:2a" ];
    };
    expected = [ ];
  };
  testOverlappingNetworksFail = {
    expr = fails "hodon.networks.main and hodon.networks.wide overlap" {
      hodon.networks.wide.ipv4.cidr = "10.10.0.0/16";
    };
    expected = true;
  };
  testDuplicateVlanFails = {
    expr = fails "VLAN 10 is assigned to more than one network: iot, main" {
      hodon.networks.iot = {
        vlanId = 10;
        ipv4.cidr = "10.20.0.0/24";
      };
    };
    expected = true;
  };
  testSeveralInterfacesNeedPrimary = {
    expr = fails "primaryInterface must name one of: main, vpn" {
      hodon.hosts.printer.interfaces.vpn = { };
    };
    expected = true;
  };
  testDanglingPrimaryInterfaceFails = {
    expr = fails "which is not one of its interfaces" {
      hodon.hosts.printer.primaryInterface = "lab";
    };
    expected = true;
  };
  testUpperCaseHostNameFails = {
    expr = fails "hodon.hosts.WYZEC1: `WYZEC1` is not a lower-case DNS label" {
      hodon.hosts.WYZEC1 = { };
    };
    expected = true;
  };
  testUnderscoreNetworkNameFails = {
    expr = fails "`smart_home` is not a lower-case DNS label" {
      hodon.networks.smart_home.ipv4.cidr = "10.20.0.0/24";
    };
    expected = true;
  };
  testRepeatedPoolNameFails = {
    expr = fails "hodon.hostnames.pool lists a name more than once" {
      hodon.hostnames.pool = [
        "pine"
        "pine"
      ];
    };
    expected = true;
  };
  testDefectsAreReportedTogether = {
    expr = lib.length (failuresOf {
      imports = [ duplicateAddress ];
      hodon.hosts.printer.interfaces.lab = { };
    });
    expected = 3;
  };
}
