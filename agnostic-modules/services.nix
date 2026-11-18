# Where each service runs.  A service is on and at `hodon.defaultHost` unless
# its own facts say otherwise.  See the Services section of USAGE.org.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ../lib/options.nix { inherit lib; }) ipv4Address;
  cfg = config.hodon;
  known = name: cfg.hosts ? ${name};

  service =
    { core }:
    {
      enable = mkOption {
        type = types.bool;
        default = core;
        description = ''
          Whether the hodon has the service.  hodix runs it when `host` is a
          host hodix manages, and someone keeps it aligned to the facts by hand
          otherwise.  False means the hodon does without it.
        '';
      };
      host = mkOption {
        type = types.str;
        default = cfg.defaultHost;
        defaultText = lib.literalMD "`hodon.defaultHost`";
        description = "The `hodon.hosts` entry the service is at.";
      };
    };

  serviceFailures =
    name: service:
    lib.optional (service.host != cfg.defaultHost && !known service.host)
      "hodon.services.${name}.host names `${
        service.host
      }`, which is not in hodon.hosts.";

  # Leases name the resolver and come from a fixed address, so both hosts
  # need one.  An unknown host is reported by serviceFailures instead.
  networkFailures =
    let
      inherit (cfg.services) dhcp dns;
      addressless = name: known name && cfg.hosts.${name}.ipv4.address == null;
    in
    lib.optional (
      dhcp.enable && addressless dhcp.host
    ) "hodon.services.dhcp is at `${dhcp.host}`, which has no fixed address."
    ++
      lib.optional (dhcp.enable && dns.enable && addressless dns.host)
        "hodon.services.dns is at `${
          dns.host
        }`, which has no fixed address, so DHCP cannot hand it out.";

  # A profile is spelled out into list groups before blocky sees it, so every
  # name has to resolve here.
  blockingFailures =
    let
      inherit (cfg.services.dns) blocking;
      path = "hodon.services.dns.blocking";
      unknownGroups = lib.filter (group: !(blocking.lists ? ${group}));
      unknownProfiles = lib.filter (profile: !(blocking.profiles ? ${profile}));
    in
    lib.optional (!(blocking.profiles ? default))
      "${
        path
      }.profiles has no `default`, which every device the facts do not name gets."
    ++ lib.concatLists (
      lib.mapAttrsToList (
        profile: groups:
        map (
          group:
          "${path}.profiles.${profile} names `${group}`, which is not in ${
            path
          }.lists."
        ) (unknownGroups groups)
      ) blocking.profiles
    )
    ++ map (
      group:
      "${path}.allowlists.${group} is not in ${
        path
      }.lists, so it would refuse every other name."
    ) (unknownGroups (lib.attrNames blocking.allowlists))
    ++ lib.concatLists (
      lib.mapAttrsToList (
        name: host:
        map (
          profile:
          "hodon.hosts.${name}.blockProfiles names `${
            profile
          }`, which is not in ${path}.profiles."
        ) (unknownProfiles host.blockProfiles)
      ) cfg.hosts
    );
in
{
  imports = [ ./facts.nix ];

  options.hodon.services = {
    dhcp = service { core = true; };
    dns = service { core = true; } // {
      upstream = mkOption {
        type = types.listOf ipv4Address;
        default = [ ];
        example = [ "9.9.9.9" ];
        description = ''
          The resolvers the hodon's DNS forwards outside names to.  Empty
          means it resolves them itself from the root servers down, so no
          public resolver sees the hodon's queries.
        '';
      };
      blocking = {
        lists = mkOption {
          type = types.attrsOf (types.listOf types.str);
          default = {
            ads = [
              "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
              "https://big.oisd.nl/domainswild"
              "https://blocklistproject.github.io/Lists/ads.txt"
              "https://blocklistproject.github.io/Lists/tracking.txt"
            ];
            adult = [ "https://blocklistproject.github.io/Lists/porn.txt" ];
            malware = [
              "https://blocklistproject.github.io/Lists/abuse.txt"
              "https://blocklistproject.github.io/Lists/crypto.txt"
              "https://blocklistproject.github.io/Lists/fraud.txt"
              "https://blocklistproject.github.io/Lists/phishing.txt"
              "https://blocklistproject.github.io/Lists/piracy.txt"
              "https://blocklistproject.github.io/Lists/ransomware.txt"
              "https://blocklistproject.github.io/Lists/scam.txt"
            ];
            social = [
              "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/social-only/hosts"
            ];
          };
          description = ''
            Groups of domains the hodon's DNS refuses.  Each source is the URL
            of a hosts file or a list of domains.  `profiles` says which hosts
            a group applies to.
          '';
        };
        allowlists = mkOption {
          type = types.attrsOf (types.listOf types.str);
          default = {
            ads = [
              "https://raw.githubusercontent.com/ShadowWhisperer/BlockLists/master/Whitelists/Whitelist"
            ];
          };
          description = ''
            Domains a group answers although one of its sources lists them.
            The default rescues names the `ads` sources are known to get
            wrong.  A group here must also be in `lists`, since blocky refuses
            every other name for a group that only allows.
          '';
        };
        profiles = mkOption {
          type = types.attrsOf (types.listOf types.str);
          default = {
            default = [
              "ads"
              "adult"
              "malware"
            ];
            adult = [
              "ads"
              "malware"
            ];
            child = [
              "ads"
              "adult"
              "malware"
              "social"
            ];
            unrestricted = [ ];
          };
          description = ''
            Named sets of `lists` groups.  A host's `blockProfiles` names
            them.  `default` applies to a device the facts do not name, so it
            is required.  An empty set refuses nothing.
          '';
        };
      };
    };
    ldap = service { core = true; };
  };

  config.hodix.facts.failures =
    lib.concatLists (lib.mapAttrsToList serviceFailures cfg.services)
    ++ networkFailures
    ++ blockingFailures;
}
