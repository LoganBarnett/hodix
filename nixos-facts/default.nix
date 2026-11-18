# Every facts profile a NixOS host applies.
{ ... }:
{
  imports = [
    ../system-facts/default.nix
    ./deploy-target.nix
    ./network.nix
    ./dns.nix
    ./dns-recursor.nix
    ./dns-zone.nix
    ./dhcp.nix
    ./ldap-server.nix
  ];
}
