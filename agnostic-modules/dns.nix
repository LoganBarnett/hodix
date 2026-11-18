# DNS management from facts.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ../lib/options.nix { inherit lib; }) notLabel notLabels;
  cfg = config.hodix.dns;
  hosts = config.hodon.hosts;

  failures = lib.concatLists [
    (map (alias: "hodix.dns.aliases.${alias}: ${notLabel alias}") (
      notLabels (lib.attrNames cfg.aliases)
    ))
    (lib.mapAttrsToList (
      alias: _: "hodix.dns.aliases.${alias} is also a host name."
    ) (lib.filterAttrs (alias: _: hosts ? ${alias}) cfg.aliases))
    (lib.mapAttrsToList (
      alias: host:
      "hodix.dns.aliases.${alias} names `${host}`, which is not in hodon.hosts."
    ) (lib.filterAttrs (_: host: !(hosts ? ${host})) cfg.aliases))
  ];
in
{
  imports = [ ./facts.nix ];

  options.hodix.dns.aliases = mkOption {
    type = types.attrsOf types.str;
    default = { };
    example = {
      ldap = "balcony";
    };
    description = ''
      Names under the hodon's domain and the `hodon.hosts` entry each points
      at.
      `ldap = "balcony"` makes `ldap.home.hodon.internal` a CNAME for
      `balcony.home.hodon.internal`.  A service profile declares its alias
      whatever host it is evaluated on, so the host serving DNS sees every
      one.
    '';
  };

  config.hodix.facts.failures = failures;
}
