# The resolver for names outside the hodon.  unbound walks down from the root
# servers itself, so no public resolver sees the hodon's queries, and a
# blocklist zone that refuses shared resolvers answers it.  It forwards
# instead when `hodon.services.dns.upstream` names resolvers.
{ config, lib, ... }:
let
  dns = config.hodon.services.dns;
  here = dns.enable && dns.host == config.hodix.hostName;
in
{
  config = lib.mkIf here {
    services.unbound = {
      enable = true;
      # blocky is the host's resolver.
      resolveLocalQueries = false;
      settings = {
        server = {
          # blocky holds 53 and dnsmasq 5335.  5354 is a coin flip.
          port = 5354;
          hide-identity = true;
          hide-version = true;
          harden-glue = true;
          harden-dnssec-stripped = true;
          harden-below-nxdomain = true;
          qname-minimisation = true;
          prefetch = true;
          prefetch-key = true;
          serve-expired = true;
        };
        forward-zone = lib.optional (dns.upstream != [ ]) {
          name = ".";
          forward-addr = dns.upstream;
        };
      };
    };
  };
}
