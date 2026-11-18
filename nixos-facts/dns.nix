# The facts layer for DNS resolution.  Blocky takes each query, refuses the
# domains the asking host's block profiles name, sends the hodon's own names to
# dnsmasq, and sends the rest to unbound.  Blocky stands in front because it
# tells hosts apart by the address a query comes from.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config) hodon;
  ipv4 = import ../lib/ipv4.nix { inherit lib; };
  dns = hodon.services.dns;
  here = dns.enable && dns.host == config.hodix.hostName;
  host = config.hodix.host;
  zone =
    "127.0.0.1:${toString (lib.head config.services.dnsmasq.settings.port)}";
  recursor =
    "127.0.0.1:${toString config.services.unbound.settings.server.port}";
  # The groups a host's profiles name.  blocky reads an empty list as no entry
  # and falls back to `default`, so refusing nothing names an empty group.
  groupsOf =
    profiles:
    let
      groups = lib.unique (
        lib.concatMap (profile: dns.blocking.profiles.${profile}) profiles
      );
    in
    if groups == [ ] then [ "none" ] else groups;
  # Every name blocky can see a host under.  The serving host's own queries
  # arrive over loopback.
  keysOf =
    other:
    [
      other.name
      other.fqdn
    ]
    ++ lib.filter (address: address != null) (
      lib.mapAttrsToList (_: interface: interface.ipv4.address) other.interfaces
    )
    ++ lib.optionals (other.name == host.name) [
      "127.0.0.1"
      "::1"
    ];
  clientGroups =
    lib.listToAttrs (
      lib.concatMap (
        other:
        map (key: lib.nameValuePair key (groupsOf other.blockProfiles)) (
          keysOf other
        )
      ) (lib.attrValues hodon.hosts)
    )
    // {
      default = groupsOf [ "default" ];
    };
  reverseZones = lib.listToAttrs (
    lib.mapAttrsToList (
      _: network: lib.nameValuePair (ipv4.reverseZone network.ipv4.cidr) zone
    ) hodon.networks
  );
in
{
  config = lib.mkIf here {
    services.blocky = {
      enable = true;
      settings = {
        ports.dns = 53;
        upstreams.groups.default = [ recursor ];
        # The list sources are fetched by name while this host's own resolver
        # is blocky itself.
        bootstrapDns = [ { upstream = recursor; } ];
        conditional.mapping = reverseZones // {
          ${hodon.domain} = zone;
        };
        # A device is named by the reverse record of its address, which
        # dnsmasq holds for fixed hosts and leases alike.
        clientLookup = {
          upstream = zone;
          singleNameOrder = [ 1 ];
        };
        blocking = {
          # blocky reads an entry holding a newline as the list itself.
          denylists = dns.blocking.lists // {
            none = [ "# Nothing is refused.\n" ];
          };
          allowlists = dns.blocking.allowlists;
          clientGroupsBlock = clientGroups;
          # A refused answer is cached for a minute, so unblocking a name takes
          # effect about as fast.  The minute is a coin flip.
          blockTTL = "60s";
          loading = {
            # The lists load once the listener is up, so a restart costs a
            # window with less blocking rather than one with no DNS.
            strategy = "fast";
            # The timeout bounds the download and the parse together, and a
            # list of a million names takes far longer than blocky's five
            # seconds.
            downloads.timeout = "60s";
          };
        };
      };
    };
    systemd.services.blocky = {
      after = [
        "dnsmasq.service"
        "unbound.service"
      ];
      wants = [ "dnsmasq.service" ];
      requires = [ "unbound.service" ];
      # blocky cannot tell systemd when it answers, so systemd asks it until
      # it does.  A unit ordered after nss-lookup.target then finds DNS up.
      serviceConfig.ExecStartPost = pkgs.writeShellScript "blocky-answers" ''
        for _ in $(seq 60); do
          ${lib.getExe config.services.blocky.package} healthcheck && exit 0
          sleep 1
        done
        exit 1
      '';
      # The target follows blocky down and back up, so it is reached only
      # while blocky answers.
      requiredBy = [ "nss-lookup.target" ];
      unitConfig.PropagatesStopTo = "nss-lookup.target";
    };
    networking = {
      # systemd-resolved's stub holds port 53 on loopback, so the host
      # resolves through blocky with a resolv.conf written from these.
      nameservers = [ "127.0.0.1" ];
      search = [ hodon.domain ];
      firewall = {
        allowedTCPPorts = [ 53 ];
        allowedUDPPorts = [ 53 ];
      };
    };
    services.resolved.enable = false;
  };
}
