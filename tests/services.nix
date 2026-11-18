{ lib, hodix }:
let
  inherit (hodix.lib) mkHodon;

  hodonOf =
    extra:
    (mkHodon {
      modules = [
        ./home.nix
        extra
      ];
    }).hodon;
  failuresOf =
    extra:
    (lib.evalModules {
      modules = [
        ../agnostic-modules/services.nix
        ./home.nix
        extra
      ];
    }).config.hodix.facts.failures;
  fails = needle: extra: lib.any (lib.hasInfix needle) (failuresOf extra);
  rejects = value: !(builtins.tryEval (builtins.deepSeq value value)).success;

  # A second NixOS host with nothing on it, so a service can move there.
  shed.hodon.hosts.shed = {
    system = "x86_64-linux";
    interfaces.main.ipv4.address = "10.10.0.10";
  };

  hodon = hodonOf { };
in
{
  testACoreServiceIsOnAtTheDefaultHost = {
    expr = {
      inherit (hodon.services.ldap) enable host;
    };
    expected = {
      enable = true;
      host = "balcony";
    };
  };
  testAServiceMovesByOneFact = {
    expr =
      (hodonOf {
        imports = [ shed ];
        hodon.services.ldap.host = "shed";
      }).services.ldap.host;
    expected = "shed";
  };
  testGoodServicesHaveNoFailures = {
    expr = failuresOf { };
    expected = [ ];
  };
  testTheDefaultHostMustExist = {
    expr = fails "hodon.defaultHost names `nope`, which is not in hodon.hosts" {
      hodon.defaultHost = lib.mkForce "nope";
    };
    expected = true;
  };
  testTheDefaultHostMustBeManaged = {
    expr = fails "hodon.defaultHost names `printer`, which is not managed" {
      hodon.defaultHost = lib.mkForce "printer";
    };
    expected = true;
  };
  # The services that default to it would each repeat the defect.
  testABadDefaultHostIsReportedOnce = {
    expr = lib.length (failuresOf {
      hodon.defaultHost = lib.mkForce "nope";
    });
    expected = 1;
  };
  testAManagedHostWithNoSystemIsReportedOnce = {
    expr = lib.length (failuresOf {
      hodon.hosts.balcony.system = lib.mkForce null;
    });
    expected = 1;
  };
  testAServiceHostMustExist = {
    expr =
      fails "hodon.services.ldap.host names `nope`, which is not in hodon.hosts"
        {
          hodon.services.ldap.host = "nope";
        };
    expected = true;
  };
  # hodix does not manage the host, so someone else runs the service there.
  testAServiceAtAnUnmanagedHostIsKeptByHand = {
    expr = failuresOf {
      hodon.services.ldap.host = "printer";
    };
    expected = [ ];
  };
  # Nothing runs it there yet, and that is hodix's gap and not the facts'.
  testAServiceAtADarwinHostIsLegal = {
    expr = failuresOf {
      hodon.services.ldap.host = "patio";
    };
    expected = [ ];
  };
  testAServiceOffIsAbsent = {
    expr = failuresOf {
      hodon.services.ldap.enable = false;
    };
    expected = [ ];
  };
  testAnUnknownServiceIsRejected = {
    expr = rejects (hodonOf {
      hodon.services.ldpa.host = "balcony";
    });
    expected = true;
  };
  testServiceFailuresRejectTheHodon = {
    expr = rejects (hodonOf {
      hodon.services.ldap.host = "nope";
    });
    expected = true;
  };
  testServicesArePureData = {
    expr = builtins.fromJSON (builtins.toJSON hodon.services) == hodon.services;
    expected = true;
  };
  testLeasesAndNamesAreOnAtTheDefaultHost = {
    expr = map (service: { inherit (hodon.services.${service}) enable host; }) [
      "dhcp"
      "dns"
    ];
    expected = [
      {
        enable = true;
        host = "balcony";
      }
      {
        enable = true;
        host = "balcony";
      }
    ];
  };
  testOutsideNamesAreResolvedFromTheRootByDefault = {
    expr = hodon.services.dns.upstream;
    expected = [ ];
  };
  testUpstreamResolversCanBeNamed = {
    expr =
      (hodonOf { hodon.services.dns.upstream = [ "9.9.9.9" ]; })
      .services.dns.upstream;
    expected = [ "9.9.9.9" ];
  };
  testEveryHostIsOnTheDefaultProfile = {
    expr = lib.unique (
      lib.mapAttrsToList (_: host: host.blockProfiles) hodon.hosts
    );
    expected = [ [ "default" ] ];
  };
  testTheDefaultProfileIsRequired = {
    expr = fails "hodon.services.dns.blocking.profiles has no `default`" {
      hodon.services.dns.blocking.profiles = lib.mkForce {
        adult = [ "ads" ];
      };
    };
    expected = true;
  };
  testAProfileNamesKnownLists = {
    expr =
      fails
        "hodon.services.dns.blocking.profiles.child names `gaming`, which is not in hodon.services.dns.blocking.lists"
        {
          hodon.services.dns.blocking.profiles.child = [ "gaming" ];
        };
    expected = true;
  };
  testAnAllowlistNeedsItsDenylist = {
    expr =
      fails
        "hodon.services.dns.blocking.allowlists.gaming is not in hodon.services.dns.blocking.lists, so it would refuse every other name"
        {
          hodon.services.dns.blocking.allowlists.gaming = [
            "https://example.com/allow.txt"
          ];
        };
    expected = true;
  };
  testAHostNamesKnownProfiles = {
    expr =
      fails
        "hodon.hosts.printer.blockProfiles names `guest`, which is not in hodon.services.dns.blocking.profiles"
        {
          hodon.hosts.printer.blockProfiles = [ "guest" ];
        };
    expected = true;
  };
  testAnEmptyProfileIsLegal = {
    expr = failuresOf {
      hodon.hosts.printer.blockProfiles = [ "unrestricted" ];
    };
    expected = [ ];
  };
  testLeasesComeFromAFixedAddress = {
    expr =
      fails "hodon.services.dhcp is at `shed`, which has no fixed address"
        {
          hodon.hosts.shed.system = "x86_64-linux";
          hodon.services.dhcp.host = "shed";
        };
    expected = true;
  };
  testLeasesNameAFixedResolver = {
    expr =
      fails
        "hodon.services.dns is at `shed`, which has no fixed address, so DHCP cannot hand it out"
        {
          hodon.hosts.shed.system = "x86_64-linux";
          hodon.services.dns.host = "shed";
        };
    expected = true;
  };
}
