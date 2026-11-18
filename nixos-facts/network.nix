# The facts layer for the host's own links.  An interface with a fixed address
# is configured by systemd-networkd and found by its hardware address, so no
# device name is written anywhere unless the facts give one.  Every other link
# takes a lease.
{ config, lib, ... }:
let
  inherit (config) hodon;
  host = config.hodix.host;
  dns = hodon.services.dns;
  # Where devices reach the hodon's DNS.  Null when hodix knows no address.
  resolver =
    if dns.enable then hodon.hosts.${dns.host}.ipv4.address or null else null;
  fixed = lib.filterAttrs (
    _: interface:
    interface.ipv4.address != null && hodon.networks ? ${interface.network}
  ) host.interfaces;
  found = interface: interface.macAddresses != [ ] || interface.device != null;
in
{
  config = {
    assertions = lib.mapAttrsToList (label: interface: {
      assertion = found interface;
      message = "hodon.hosts.${host.name}.interfaces.${
        label
      } has a fixed address and neither macAddresses nor device, so its link cannot be found.";
    }) fixed;
    networking.useNetworkd = lib.mkDefault true;
    systemd.network.networks = lib.mapAttrs' (
      label: interface:
      let
        network = hodon.networks.${interface.network};
      in
      lib.nameValuePair "10-${label}" {
        matchConfig =
          if interface.macAddresses != [ ] then
            { MACAddress = lib.concatStringsSep " " interface.macAddresses; }
          else
            lib.optionalAttrs (interface.device != null) {
              Name = interface.device;
            };
        address = [
          "${interface.ipv4.address}/${toString network.ipv4.prefixLength}"
        ];
        # One default route, through the primary interface's network.
        gateway = lib.optional (
          label == host.primaryInterface && network.ipv4.gateway != null
        ) network.ipv4.gateway;
        dns = lib.optional (resolver != null) resolver;
        domains = [ hodon.domain ];
        networkConfig.DHCP = "no";
      }
    ) fixed;
  };
}
