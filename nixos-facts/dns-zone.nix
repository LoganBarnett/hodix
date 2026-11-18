# The hodon's own zone.  dnsmasq answers for every fixed host, every alias,
# and every lease, and blocky sends it the names under the hodon's domain and
# the reverse zones of its networks.  dhcp.nix shares the daemon.
{ config, lib, ... }:
let
  inherit (config) hodon;
  dns = hodon.services.dns;
  here = dns.enable && dns.host == config.hodix.hostName;
  named = lib.filterAttrs (_: host: host.ipv4.address != null) hodon.hosts;
  # An alias to an unknown host is reported by the alias module.
  aliases = lib.filterAttrs (
    _: host: hodon.hosts ? ${host}
  ) config.hodix.dns.aliases;
in
{
  config = lib.mkIf here {
    services.dnsmasq = {
      enable = true;
      # blocky is the host's resolver.
      resolveLocalQueries = false;
      settings = {
        # blocky holds 53.  5353 is mDNS and 5355 is LLMNR, and a discovery
        # daemon bound to either with address reuse is handed the queries
        # meant for dnsmasq.  5335 is unassigned and otherwise a coin flip.
        port = 5335;
        domain = hodon.domain;
        local = [ "/${hodon.domain}/" ];
        # The facts are the whole zone, so nothing is read from /etc/hosts or
        # /etc/resolv.conf, and a bare name is completed with the domain.
        expand-hosts = true;
        no-hosts = true;
        no-resolv = true;
        domain-needed = true;
        bogus-priv = true;
        host-record = lib.mapAttrsToList (
          _: host: "${host.fqdn},${host.ipv4.address}"
        ) named;
        cname = lib.mapAttrsToList (
          alias: host: "${alias}.${hodon.domain},${hodon.hosts.${host}.fqdn}"
        ) aliases;
      };
    };
    # blocky asks dnsmasq for the hodon's names, so DNS is up only once both
    # answer.
    systemd.services.dnsmasq = {
      before = [ "nss-lookup.target" ];
      requiredBy = [ "nss-lookup.target" ];
      unitConfig.PropagatesStopTo = "nss-lookup.target";
    };
  };
}
