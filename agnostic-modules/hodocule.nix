# The hodon's view of its hodocule.  Federation is pairwise, so the hodocule is
# the set of peers this hodon has shaken hands with.  Each peer entry is the
# card the peer wrote plus what this hodon decides about it.  See the Hodocule
# section of README.org.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ../lib/options.nix { inherit lib; })
    derived
    notLabel
    notLabels
    pemCertificate
    wireguardEndpoint
    wireguardKey
    ;
  cfg = config.hodon;

  # identity.nix declares hodon.groups.  This adds the federation flag to it.
  exportModule.options.exported = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether peers may admit this hodon's users by this group.  The hodon
      attests membership to them, so the name goes in the card.
    '';
  };

  peerModule =
    { name, ... }:
    {
      options = {
        name = derived {
          type = types.str;
          description = "The peer's name.  It is the attribute name.";
          value = name;
        };
        domain = derived {
          type = types.str;
          description = "The peer's internal domain.";
          value = "${name}.hodon.internal";
        };
        rootCertificate = mkOption {
          type = pemCertificate;
          description = ''
            The CA certificate the peer's services chain to, from its card.
            A device re-signs its key under a name constraint before trusting
            it, so a root or an intermediate both serve.
          '';
        };
        wireguard = {
          publicKey = mkOption {
            type = wireguardKey;
            description = "The peer's WireGuard public key, from its card.";
          };
          endpoint = mkOption {
            type = types.nullOr wireguardEndpoint;
            default = null;
            example = "vpn.example.net:51820";
            description = ''
              Where the peer listens, from its card.  Null means the peer
              cannot be reached first, so this hodon must have an endpoint.
            '';
          };
        };
        groups = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "family" ];
          description = ''
            The groups the peer attests membership for, from its card.  A
            grant by group names one of these.
          '';
        };
      };
    };

  peers = cfg.hodocule.peers;
  unreachable = lib.filterAttrs (
    _: peer: peer.wireguard.endpoint == null && cfg.wireguard.endpoint == null
  ) peers;

  failures = lib.concatLists [
    (map (name: "hodon.hodocule.peers.${name}: ${notLabel name}") (
      notLabels (lib.attrNames peers)
    ))
    (lib.optional (peers ? ${cfg.name})
      "hodon.hodocule.peers.${cfg.name} has the hodon's own name."
    )
    (lib.mapAttrsToList (
      name: _:
      "hodon.hodocule.peers.${
        name
      }.wireguard.endpoint and hodon.wireguard.endpoint are both null, so neither side can open the link."
    ) unreachable)
  ];
in
{
  imports = [ ./identity.nix ];

  options.hodon = {
    rootCertificate = mkOption {
      type = types.nullOr pemCertificate;
      default = null;
      description = ''
        The CA certificate the hodon's services chain to.  It goes in the
        hodon's card.  Null means the hodon has no CA yet and cannot federate.
      '';
    };
    wireguard = {
      publicKey = mkOption {
        type = types.nullOr wireguardKey;
        default = null;
        description = ''
          The public key of the hodon's federation link.  It goes in the
          hodon's card.
        '';
      };
      endpoint = mkOption {
        type = types.nullOr wireguardEndpoint;
        default = null;
        example = "vpn.example.net:51820";
        description = ''
          Where the hodon's federation link listens.  It goes in the hodon's
          card.  Null means peers must reach out first.
        '';
      };
    };
    groups = mkOption { type = types.attrsOf (types.submodule exportModule); };
    hodocule = {
      peers = mkOption {
        type = types.attrsOf (types.submodule peerModule);
        default = { };
        description = ''
          The hodons this hodon federates with, by name.  Federation is not
          transitive, so a peer's peers are not listed here.
        '';
      };
      domains = derived {
        type = types.listOf types.str;
        description = ''
          The hodon's own domain and every peer's.  A roaming device routes
          exactly these through its tunnel home.
        '';
        value = [
          cfg.domain
        ]
        ++ lib.mapAttrsToList (_: peer: peer.domain) peers;
      };
    };
  };

  config.hodix.facts.failures = failures;
}
