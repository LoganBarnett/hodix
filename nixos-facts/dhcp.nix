# The facts layer for leases.  The host the facts place `dhcp` on hands every
# device on its networks an address, the hodon's resolver, and the gateway.  A
# host named in the facts always gets its fixed address, and one without gets
# its name.  dnsmasq serves it, shared with dns-zone.nix when both land on one
# host.
{ config, lib, ... }:
let
  inherit (config) hodon;
  inherit (hodon.services) dhcp dns;
  here = dhcp.enable && dhcp.host == config.hodix.hostName;
  dnsHere = dns.enable && dns.host == config.hodix.hostName;
  host = config.hodix.host;
  resolver =
    if dns.enable then hodon.hosts.${dns.host}.ipv4.address or null else null;
  fixedOn =
    other:
    lib.filterAttrs (
      _: interface:
      interface.ipv4.address != null && hodon.networks ? ${interface.network}
    ) other.interfaces;
  # The networks this host has a fixed address on that hand out leases.
  served = lib.filter (name: hodon.networks.${name}.ipv4.leases != null) (
    lib.unique (
      lib.mapAttrsToList (_: interface: interface.network) (fixedOn host)
    )
  );
  # One reservation per fixed interface on a served network.  The host's name
  # rides on its primary interface alone, since dnsmasq takes each name once.
  # An interface with no hardware address is found by that name, so one that
  # is not primary has no reservation.
  reservations = lib.concatLists (
    lib.mapAttrsToList (
      name: other:
      lib.concatLists (
        lib.mapAttrsToList (
          label: interface:
          let
            primary = label == other.primaryInterface;
          in
          lib.optional
            (
              lib.elem interface.network served
              && (primary || interface.macAddresses != [ ])
            )
            (
              lib.concatStringsSep "," (
                interface.macAddresses
                ++ lib.optional primary name
                ++ [ interface.ipv4.address ]
              )
            )
        ) (fixedOn other)
      )
    ) hodon.hosts
  );
  # A host with no fixed address is named on its lease, so the zone and blocky
  # know the device by its facts name.  Every hardware address goes on one
  # line, since a device presents one of them at a time.
  named = lib.concatLists (
    lib.mapAttrsToList (
      name: other:
      let
        macs = lib.concatMap (interface: interface.macAddresses) (
          lib.filter (interface: lib.elem interface.network served) (
            lib.attrValues other.interfaces
          )
        );
      in
      lib.optional (lib.attrNames (fixedOn other) == [ ] && macs != [ ]) (
        lib.concatStringsSep "," (macs ++ [ name ])
      )
    ) hodon.hosts
  );
  options =
    network:
    let
      inherit (hodon.networks.${network}.ipv4) gateway;
    in
    [ "tag:${network},option:domain-search,${hodon.domain}" ]
    ++ lib.optional (gateway != null) "tag:${network},option:router,${gateway}"
    ++
      lib.optional (resolver != null)
        "tag:${network},option:dns-server,${resolver}";
  range =
    network:
    let
      inherit (hodon.networks.${network}.ipv4) leases;
    in
    # Twelve hours is a coin flip.
    "set:${network},${leases.from},${leases.to},12h";
in
{
  config = lib.mkIf here {
    services.dnsmasq = {
      enable = true;
      # blocky here or the hodon's DNS elsewhere resolves for this host.
      resolveLocalQueries = false;
      settings = {
        # Without DNS here the daemon only leases.
        port = lib.mkIf (!dnsHere) 0;
        dhcp-range = map range served;
        dhcp-host = reservations ++ named;
        dhcp-option = lib.concatMap options served;
      };
    };
    networking.firewall.allowedUDPPorts = [ 67 ];
  };
}
