{
  lib,
  nixpkgs,
  hodix,
}:
let
  profiles = [
    hodix.nixosModules.default
    ../system-facts/host.nix
    ../nixos-facts/network.nix
    ../nixos-facts/dns.nix
    ../nixos-facts/dns-recursor.nix
    ../nixos-facts/dns-zone.nix
    ../nixos-facts/dhcp.nix
  ];
  # The named host under the fixture facts plus `facts`.
  nixos =
    name: facts:
    (nixpkgs.lib.nixosSystem {
      specialArgs = hodix.lib.specialArgs;
      modules = profiles ++ [
        (
          (hodix.lib.mkHodon {
            modules = [
              ./home.nix
              facts
            ];
          }).forHost
            name
        )
        { system.stateVersion = "26.05"; }
      ];
    }).config;
  balcony = nixos "balcony" { };
  # A second NixOS host with a fixed address, so a service can move there.
  shed.hodon.hosts.shed = {
    system = "x86_64-linux";
    interfaces.main = {
      ipv4.address = "10.10.0.10";
      macAddresses = [ "00:00:5e:00:53:03" ];
    };
  };
  main = balcony.systemd.network.networks."10-main";
  blocky = balcony.services.blocky.settings;
  dnsmasq = balcony.services.dnsmasq.settings;
  unbound = balcony.services.unbound.settings;
  zone = "127.0.0.1:5335";
  failedAssertions =
    configuration:
    map (entry: entry.message) (
      lib.filter (entry: !entry.assertion) configuration.assertions
    );
in
{
  testHostsRunNetworkd = {
    expr = balcony.networking.useNetworkd;
    expected = true;
  };
  testAFixedInterfaceIsFoundByItsHardwareAddress = {
    expr = main.matchConfig;
    expected = {
      MACAddress = "00:00:5e:00:53:01";
    };
  };
  testAFixedInterfaceHasItsAddressRouteAndResolver = {
    expr = {
      inherit (main)
        address
        gateway
        dns
        domains
        ;
      dhcp = main.networkConfig.DHCP;
    };
    expected = {
      address = [ "10.10.0.9/24" ];
      gateway = [ "10.10.0.1" ];
      dns = [ "10.10.0.9" ];
      domains = [ "home.hodon.internal" ];
      dhcp = "no";
    };
  };
  testATunnelIsFoundByItsDeviceName = {
    expr = balcony.systemd.network.networks."10-vpn".matchConfig;
    expected = {
      Name = "wg0";
    };
  };
  testOnlyThePrimaryInterfaceCarriesTheDefaultRoute = {
    expr = balcony.systemd.network.networks."10-vpn".gateway;
    expected = [ ];
  };
  testAnInterfaceWithNoLinkIsRejected = {
    expr = lib.any (lib.hasInfix "neither macAddresses nor device") (
      failedAssertions (
        nixos "balcony" {
          hodon.hosts.balcony.interfaces.main.macAddresses = lib.mkForce [ ];
        }
      )
    );
    expected = true;
  };
  testBlockyAnswersOnTheDnsPort = {
    expr = blocky.ports.dns;
    expected = 53;
  };
  testOutsideNamesGoToTheRecursor = {
    expr = {
      inherit (blocky) upstreams bootstrapDns;
    };
    expected = {
      upstreams.groups.default = [ "127.0.0.1:5354" ];
      bootstrapDns = [ { upstream = "127.0.0.1:5354"; } ];
    };
  };
  testTheHodonsNamesAndReverseZonesGoToTheZone = {
    expr = blocky.conditional.mapping;
    expected = {
      "home.hodon.internal" = zone;
      "0.10.10.in-addr.arpa" = zone;
      "102.168.192.in-addr.arpa" = zone;
    };
  };
  testADeviceIsNamedByItsReverseRecord = {
    expr = blocky.clientLookup;
    expected = {
      upstream = zone;
      singleNameOrder = [ 1 ];
    };
  };
  testTheListsAreTheFacts = {
    expr = {
      denylists = lib.attrNames blocky.blocking.denylists;
      allowlists = lib.attrNames blocky.blocking.allowlists;
    };
    expected = {
      denylists = [
        "ads"
        "adult"
        "malware"
        "none"
        "social"
      ];
      allowlists = [ "ads" ];
    };
  };
  testRefusingNothingNamesAnEmptyGroup = {
    expr = blocky.blocking.denylists.none;
    expected = [ "# Nothing is refused.\n" ];
  };
  testEveryHostIsBlockedByItsProfiles = {
    expr =
      (nixos "balcony" {
        hodon.hosts = {
          patio.blockProfiles = [ "unrestricted" ];
          printer.blockProfiles = [ "child" ];
        };
      }).services.blocky.settings.blocking.clientGroupsBlock;
    expected =
      let
        usual = [
          "ads"
          "adult"
          "malware"
        ];
        child = usual ++ [ "social" ];
      in
      {
        default = usual;
        balcony = usual;
        "balcony.home.hodon.internal" = usual;
        "10.10.0.9" = usual;
        "192.168.102.9" = usual;
        "127.0.0.1" = usual;
        "::1" = usual;
        patio = [ "none" ];
        "patio.home.hodon.internal" = [ "none" ];
        "10.10.0.20" = [ "none" ];
        printer = child;
        "printer.home.hodon.internal" = child;
      };
  };
  testRefusedAnswersExpireInAMinute = {
    expr = blocky.blocking.blockTTL;
    expected = "60s";
  };
  testTheListsLoadAfterTheListenerIsUp = {
    expr = blocky.blocking.loading.strategy;
    expected = "fast";
  };
  testBlockyWaitsForBothBackends = {
    expr =
      let
        unit = balcony.systemd.services.blocky;
      in
      {
        after = lib.filter (name: lib.elem name unit.after) [
          "dnsmasq.service"
          "unbound.service"
        ];
        inherit (unit) requires;
      };
    expected = {
      after = [
        "dnsmasq.service"
        "unbound.service"
      ];
      requires = [ "unbound.service" ];
    };
  };
  testTheDnsHostResolvesThroughBlocky = {
    expr = {
      inherit (balcony.networking) nameservers search;
      resolved = balcony.services.resolved.enable;
    };
    expected = {
      nameservers = [ "127.0.0.1" ];
      search = [ "home.hodon.internal" ];
      resolved = false;
    };
  };
  testTheRecursorIsOnLoopback = {
    expr = {
      inherit (unbound.server) port interface;
      inherit (unbound) forward-zone;
    };
    expected = {
      port = 5354;
      interface = [
        "127.0.0.1"
        "::1"
      ];
      forward-zone = [ ];
    };
  };
  testNamedUpstreamsAreForwarded = {
    expr =
      (nixos "balcony" { hodon.services.dns.upstream = [ "9.9.9.9" ]; })
      .services.unbound.settings.forward-zone;
    expected = [
      {
        name = ".";
        forward-addr = [ "9.9.9.9" ];
      }
    ];
  };
  testTheDnsHostAnswersForEveryFixedHost = {
    expr = dnsmasq.host-record;
    expected = [
      "balcony.home.hodon.internal,10.10.0.9"
      "patio.home.hodon.internal,10.10.0.20"
    ];
  };
  testAnAliasIsACnameToItsHost = {
    expr =
      (nixos "balcony" { hodix.dns.aliases.ldap = "balcony"; })
      .services.dnsmasq.settings.cname;
    expected = [ "ldap.home.hodon.internal,balcony.home.hodon.internal" ];
  };
  testTheZoneIsTheFactsAlone = {
    expr = {
      inherit (dnsmasq)
        domain
        local
        no-hosts
        no-resolv
        port
        server
        ;
    };
    # The settings type keeps every value as a list.
    expected = {
      domain = [ "home.hodon.internal" ];
      local = [ "/home.hodon.internal/" ];
      no-hosts = [ true ];
      no-resolv = [ true ];
      port = [ 5335 ];
      server = [ ];
    };
  };
  # The tunnel network hands out nothing, so only main has a range.
  testLeasesCoverTheUpperHalfOfEachServedNetwork = {
    expr = dnsmasq.dhcp-range;
    expected = [ "set:main,10.10.0.128,10.10.0.254,12h" ];
  };
  testEveryKnownDeviceIsReserved = {
    expr = dnsmasq.dhcp-host;
    expected = [
      "00:00:5e:00:53:01,balcony,10.10.0.9"
      "patio,10.10.0.20"
      "00:00:5e:00:53:02,printer"
    ];
  };
  testDevicesLearnTheDomainRouterAndResolver = {
    expr = dnsmasq.dhcp-option;
    expected = [
      "tag:main,option:domain-search,home.hodon.internal"
      "tag:main,option:router,10.10.0.1"
      "tag:main,option:dns-server,10.10.0.9"
    ];
  };
  testTheServingHostOpensItsPorts = {
    expr = {
      tcp = balcony.networking.firewall.allowedTCPPorts;
      udp = lib.sort lib.lessThan balcony.networking.firewall.allowedUDPPorts;
    };
    expected = {
      tcp = [ 53 ];
      udp = [
        53
        67
      ];
    };
  };
  testAHostElsewhereServesNothing = {
    expr =
      let
        elsewhere = nixos "shed" shed;
      in
      map (service: elsewhere.services.${service}.enable) [
        "blocky"
        "dnsmasq"
        "unbound"
      ];
    expected = [
      false
      false
      false
    ];
  };
  testAHostElsewhereResolvesAtTheDnsHost = {
    expr = (nixos "shed" shed).systemd.network.networks."10-main".dns;
    expected = [ "10.10.0.9" ];
  };
  testALeaseOnlyHostKeepsDnsOff = {
    expr =
      let
        configuration = nixos "shed" {
          imports = [ shed ];
          hodon.services.dhcp.host = "shed";
        };
      in
      {
        inherit (configuration.services.dnsmasq) enable resolveLocalQueries;
        inherit (configuration.services.dnsmasq.settings) port;
      };
    expected = {
      enable = true;
      resolveLocalQueries = false;
      port = [ 0 ];
    };
  };
}
