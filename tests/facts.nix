{ lib, hodix }:
let
  inherit (hodix.lib) mkHodon;
  inherit (hodix.agnosticProfiles)
    hostname-convention-bean
    hostname-convention-home
    hostname-convention-periodic-table
    hostname-convention-petal
    hostname-convention-school
    hostname-convention-wood
    ;

  good = ./home.nix;
  duplicateAddress.hodon.hosts.intruder = {
    managed = false;
    interfaces.main.ipv4.address = "10.10.0.9";
  };

  hodonOf =
    extra:
    (mkHodon {
      modules = [
        good
        extra
      ];
    }).hodon;
  # The facts module alone, so a defect elsewhere cannot hide one here.
  facts =
    extra:
    (lib.evalModules {
      modules = [
        ../agnostic-modules/facts.nix
        good
        extra
      ];
    }).config;
  failuresOf = extra: (facts extra).hodix.facts.failures;
  fails = needle: extra: lib.any (lib.hasInfix needle) (failuresOf extra);
  rejects = value: !(builtins.tryEval (builtins.deepSeq value value)).success;
  # The least a hodon needs besides its name, so a rejection is about the name.
  # The host has no address, so the network services are off.
  minimal.hodon = {
    defaultHost = "balcony";
    hosts.balcony.system = "x86_64-linux";
    services = {
      dhcp.enable = false;
      dns.enable = false;
    };
  };
  bare =
    module:
    (mkHodon {
      modules = [
        minimal
        module
      ];
    }).hodon;
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
    expr = (asHost "balcony").fqdn;
    expected = "balcony.home.hodon.internal";
  };
  testUnknownHostNameRejected = {
    expr = rejects (asHost "nope");
    expected = true;
  };
  testDomain = {
    expr = hodon.domain;
    expected = "home.hodon.internal";
  };
  testHostName = {
    expr = hodon.hosts.balcony.name;
    expected = "balcony";
  };
  testFqdn = {
    expr = hodon.hosts.balcony.fqdn;
    expected = "balcony.home.hodon.internal";
  };
  testPrimaryAddress = {
    expr = hodon.hosts.balcony.ipv4.address;
    expected = "10.10.0.9";
  };
  testOnlyInterfaceIsPrimary = {
    expr = hodon.hosts.patio.ipv4.address;
    expected = "10.10.0.20";
  };
  testDynamicAddressIsNull = {
    expr = hodon.hosts.printer.ipv4.address;
    expected = null;
  };
  testInterfaceNetworkDefaultsToItsName = {
    expr = hodon.hosts.balcony.interfaces.vpn.network;
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
          "balcony"
          "pine"
          "patio"
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
      available = 118;
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
  # The hosts of the test hodon are places outside a home, so they are taken.
  testHomeConvention = {
    expr = lib.take 4 (hostnamesWith hostname-convention-home).available;
    expected = [
      "barn"
      "coop"
      "deck"
      "lawn"
    ];
  };
  testSchoolConvention = {
    expr = lib.take 4 (hostnamesWith hostname-convention-school).available;
    expected = [
      "art"
      "bio"
      "civ"
      "gym"
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
          hostname-convention-home
          hostname-convention-petal
          hostname-convention-school
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
      hodon.name = "Home";
    });
    expected = true;
  };
  testDomainIsReadOnly = {
    expr = rejects (hodonOf {
      hodon.domain = "home";
    });
    expected = true;
  };
  testUpperCaseMacRejected = {
    expr = rejects (hodonOf {
      hodon.hosts.printer.interfaces.main = {
        macAddresses = [ "00:00:5E:00:53:03" ];
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
      hodon.hosts.barn.system = "aarch64-ios";
    });
    expected = true;
  };
  testAnyKnownSystemAccepted = {
    expr =
      (hodonOf { hodon.hosts.barn.system = "x86_64-freebsd"; })
      .hosts.barn.system;
    expected = "x86_64-freebsd";
  };
  testAHostIsManagedByDefault = {
    expr = (hodonOf { }).hosts.balcony.managed;
    expected = true;
  };
  testAManagedHostNeedsASystem = {
    expr = fails "hodon.hosts.barn is managed but has no system" {
      hodon.hosts.barn = { };
    };
    expected = true;
  };
  testAnUnmanagedHostNeedsNoSystem = {
    expr = (hodonOf { hodon.hosts.barn.managed = false; }).hosts.barn.system;
    expected = null;
  };
  testUnknownHostKeyRejected = {
    expr = rejects (hodonOf {
      hodon.hosts.printer.mac = "00:00:5e:00:53:02";
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
        "00:00:5e:00:53:01"
      ];
    };
    expected = true;
  };
  testMacOnTwoInterfacesOfOneHostPasses = {
    expr = failuresOf {
      hodon.hosts.balcony.interfaces.vpn.macAddresses = [ "00:00:5e:00:53:01" ];
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
  testLeasesDefaultToTheUpperHalf = {
    expr = (facts { }).hodon.networks.main.ipv4.leases;
    expected = {
      from = "10.10.0.128";
      to = "10.10.0.254";
    };
  };
  testATinyNetworkHandsOutNoLeases = {
    expr =
      (facts { hodon.networks.link.ipv4.cidr = "10.10.1.0/31"; })
      .hodon.networks.link.ipv4.leases;
    expected = null;
  };
  testAGatewayOutsideItsNetworkFails = {
    expr =
      fails
        "hodon.networks.main.ipv4.gateway is 10.20.0.1, which is not a host address in 10.10.0.0/24"
        { hodon.networks.main.ipv4.gateway = lib.mkForce "10.20.0.1"; };
    expected = true;
  };
  testAGatewayInsideTheLeasesFails = {
    expr =
      fails
        "hodon.networks.main.ipv4.gateway is 10.10.0.200, which is inside its leases"
        { hodon.networks.main.ipv4.gateway = lib.mkForce "10.10.0.200"; };
    expected = true;
  };
  testLeasesOutsideTheNetworkFail = {
    expr =
      fails
        "hodon.networks.main.ipv4.leases runs from 10.10.0.200 to 10.10.1.5, which is not a range of host addresses in 10.10.0.0/24"
        {
          hodon.networks.main.ipv4.leases = {
            from = "10.10.0.200";
            to = "10.10.1.5";
          };
        };
    expected = true;
  };
  testBackwardLeasesFail = {
    expr = fails "which is not a range of host addresses" {
      hodon.networks.main.ipv4.leases = {
        from = "10.10.0.200";
        to = "10.10.0.150";
      };
    };
    expected = true;
  };
  testAFixedAddressInsideTheLeasesFails = {
    expr =
      fails
        "hodon.hosts.printer.interfaces.main.ipv4.address is 10.10.0.130, which is inside the leases of hodon.networks.main"
        { hodon.hosts.printer.interfaces.main.ipv4.address = "10.10.0.130"; };
    expected = true;
  };
  testAHostIsOnTheDefaultProfile = {
    expr = (facts { }).hodon.hosts.printer.blockProfiles;
    expected = [ "default" ];
  };
}
