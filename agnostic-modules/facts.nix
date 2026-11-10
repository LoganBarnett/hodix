# Facts are declared data about a hodon that other modules read.  This module
# sets almost nothing on a host itself.  See the Facts section of README.org.
{
  config,
  lib,
  options,
  ...
}:
let
  inherit (lib) mkOption types;
  ipv4 = import ../lib/ipv4.nix { inherit lib; };
  inherit (import ../lib/options.nix { inherit lib; })
    dnsLabel
    derived
    notLabel
    notLabels
    sshEd25519PublicKey
    ;
  cfg = config.hodon;

  macAddress = types.strMatching "([0-9a-f]{2}:){5}[0-9a-f]{2}";
  # A named type keeps the octet pattern out of error messages.
  ipv4Address = lib.mkOptionType {
    name = "ipv4Address";
    description = "IPv4 address in dotted-decimal notation";
    descriptionClass = "noun";
    check = value: lib.isString value && ipv4.isAddress value;
    merge = lib.mergeEqualOption;
  };
  ipv4Cidr = lib.mkOptionType {
    name = "ipv4Cidr";
    description = "IPv4 network in CIDR notation with no host bits set";
    descriptionClass = "noun";
    check = value: lib.isString value && ipv4.parseCidr value != null;
    merge = lib.mergeEqualOption;
  };
  # An enum over the same list would print all eighty values in every error.
  nixSystem = lib.mkOptionType {
    name = "nixSystem";
    description = "Nix system double listed in lib.systems.doubles.all";
    descriptionClass = "noun";
    check = value: lib.elem value lib.systems.doubles.all;
    merge = lib.mergeEqualOption;
  };

  networkModule =
    { config, ... }:
    let
      parsed = ipv4.parseCidr config.ipv4.cidr;
    in
    {
      options = {
        vlanId = mkOption {
          type = types.nullOr (types.ints.between 1 4094);
          default = null;
          example = 10;
          description = ''
            The 802.1Q VLAN that carries this network.  Null means the network
            is untagged.
          '';
        };
        ipv4 = {
          cidr = mkOption {
            type = ipv4Cidr;
            example = "10.10.0.0/24";
            description = ''
              The network's IPv4 range.  Networks in one hodon must not
              overlap.
            '';
          };
          address = derived {
            type = types.str;
            description = "The network address of `cidr`.";
            value = parsed.address;
          };
          prefixLength = derived {
            type = types.int;
            description = "The prefix length of `cidr`.";
            value = parsed.prefixLength;
          };
        };
      };
    };

  interfaceModule =
    { name, ... }:
    {
      options = {
        network = mkOption {
          type = types.str;
          default = name;
          defaultText = lib.literalMD "the interface's attribute name";
          description = ''
            The `hodon.networks` entry this interface attaches to.
          '';
        };
        ipv4.address = mkOption {
          type = types.nullOr ipv4Address;
          default = null;
          example = "10.10.0.9";
          description = ''
            The interface's fixed address on its network.  Null means the
            address is assigned dynamically.
          '';
        };
        macAddresses = mkOption {
          type = types.listOf macAddress;
          default = [ ];
          example = [ "b8:ca:3a:77:a9:2a" ];
          description = ''
            The hardware addresses that reach this interface.  They are
            written in lower case.
          '';
        };
      };
    };

  hostModule =
    { name, config, ... }:
    let
      names = lib.attrNames config.interfaces;
      primary = config.primaryInterface;
    in
    {
      options = {
        name = derived {
          type = types.str;
          description = "The host's attribute name.";
          value = name;
        };
        fqdn = derived {
          type = types.str;
          description = "The host's name under `hodon.domain`.";
          value = "${name}.${cfg.domain}";
        };
        system = mkOption {
          type = types.nullOr nixSystem;
          default = null;
          example = "x86_64-linux";
          description = ''
            The Nix system this host is built for.  Null means the hodon does
            not build this host.  Whether hodix can build a given system is a
            property of hodix and not of the host.
          '';
        };
        interfaces = mkOption {
          type = types.attrsOf (types.submodule interfaceModule);
          default = { };
          description = ''
            The host's attachments to the hodon's networks.  Each entry is one
            address on one network.  The attribute name is a label of your
            choosing and is not the operating system's device name.
          '';
        };
        sshHostKey = mkOption {
          type = types.nullOr sshEd25519PublicKey;
          default = null;
          example = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... root@silicon";
          description = ''
            The host's ed25519 SSH host public key.  Secrets for the host are
            encrypted to it.  Null means the host can hold no secret.
          '';
        };
        primaryInterface = mkOption {
          type = types.nullOr types.str;
          default = if lib.length names == 1 then lib.head names else null;
          defaultText = lib.literalMD "the only interface, otherwise null";
          description = ''
            The interface whose address the host's name resolves to.  A host
            with several interfaces must set it.
          '';
        };
        ipv4.address = derived {
          type = types.nullOr types.str;
          description = "The address of `primaryInterface`.";
          value =
            if primary == null then
              null
            else
              config.interfaces.${primary}.ipv4.address or null;
        };
      };
    };

  interfaces = lib.concatLists (
    lib.mapAttrsToList (
      hostName: host:
      lib.mapAttrsToList (interfaceName: interface: {
        inherit hostName;
        inherit (interface) network macAddresses;
        inherit (interface.ipv4) address;
        path = "hodon.hosts.${hostName}.interfaces.${interfaceName}";
      }) host.interfaces
    ) cfg.hosts
  );
  parsedNetworks = lib.mapAttrs (
    _: network: ipv4.parseCidr network.ipv4.cidr
  ) cfg.networks;
  hasNetwork = interface: cfg.networks ? ${interface.network};
  addressed = lib.filter (interface: interface.address != null) interfaces;
  misplaced = lib.filter (
    interface:
    hasNetwork interface
    && !ipv4.isHostAddress parsedNetworks.${interface.network} interface.address
  ) addressed;
  macClaims = lib.concatMap (
    interface: map (mac: interface // { inherit mac; }) interface.macAddresses
  ) interfaces;
  hostsOf = claims: lib.unique (map (claim: claim.hostName) claims);
  networkPairs =
    let
      names = lib.attrNames cfg.networks;
    in
    lib.concatMap (
      a: map (b: { inherit a b; }) (lib.filter (b: a < b) names)
    ) names;
  vlans = lib.filter (network: network.vlanId != null) (
    lib.mapAttrsToList (name: network: {
      inherit name;
      inherit (network) vlanId;
    }) cfg.networks
  );
  shared = lib.filterAttrs (_: group: lib.length group > 1);
  detached = lib.filter (interface: !hasNetwork interface) interfaces;
  addressGroups = shared (lib.groupBy (interface: interface.address) addressed);
  # A trunked gateway presents one MAC on several networks, so only a MAC
  # shared between hosts is a defect.
  macGroups = lib.filterAttrs (_: claims: lib.length (hostsOf claims) > 1) (
    lib.groupBy (claim: claim.mac) macClaims
  );
  overlapping = lib.filter (
    pair: ipv4.overlaps parsedNetworks.${pair.a} parsedNetworks.${pair.b}
  ) networkPairs;
  vlanGroups = shared (lib.groupBy (network: toString network.vlanId) vlans);
  paths = lib.concatMapStringsSep ", " (interface: interface.path);

  failures = lib.concatLists [
    (map (name: "hodon.hosts.${name}: ${notLabel name}") (
      notLabels (lib.attrNames cfg.hosts)
    ))
    (map (name: "hodon.networks.${name}: ${notLabel name}") (
      notLabels (lib.attrNames cfg.networks)
    ))
    (map (
      interface:
      "${interface.path}.network names `${
        interface.network
      }`, which is not in hodon.networks."
    ) detached)
    (map (
      interface:
      "${interface.path}.ipv4.address is ${
        interface.address
      }, which is not a host address in ${
        cfg.networks.${interface.network}.ipv4.cidr
      }."
    ) misplaced)
    (lib.mapAttrsToList (
      address: group:
      "Address ${address} is claimed more than once: ${paths group}."
    ) addressGroups)
    (lib.mapAttrsToList (
      mac: claims:
      "MAC address ${mac} is claimed by more than one host: ${paths claims}."
    ) macGroups)
    (map (
      pair: "hodon.networks.${pair.a} and hodon.networks.${pair.b} overlap."
    ) overlapping)
    (lib.mapAttrsToList (
      vlanId: group:
      "VLAN ${vlanId} is assigned to more than one network: ${
        lib.concatMapStringsSep ", " (network: network.name) group
      }."
    ) vlanGroups)
    (lib.concatLists (
      lib.mapAttrsToList (
        name: host:
        let
          names = lib.attrNames host.interfaces;
        in
        if host.primaryInterface == null then
          lib.optional (lib.length names > 1)
            "hodon.hosts.${
              name
            } has several interfaces, so primaryInterface must name one of: ${
              lib.concatStringsSep ", " names
            }."
        else
          lib.optional (!(host.interfaces ? ${host.primaryInterface}))
            "hodon.hosts.${name}.primaryInterface names `${
              host.primaryInterface
            }`, which is not one of its interfaces."
      ) cfg.hosts
    ))
    (lib.optional (
      !lib.allUnique cfg.hostnames.pool
    ) "hodon.hostnames.pool lists a name more than once.")
  ];
in
{
  options.hodon = {
    name = mkOption {
      type = dnsLabel;
      example = "proton";
      description = ''
        The hodon's name.  It is one DNS label and it is unique within any
        hodocule the hodon joins.
      '';
    };
    domain = derived {
      type = types.str;
      description = "The hodon's internal domain.";
      value = "${cfg.name}.hodon.internal";
    };
    hostnames = {
      convention = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "periodic-table";
        description = ''
          The name of the hostname convention the hodon follows.  A hodon
          follows at most one.
        '';
      };
      pool = mkOption {
        type = types.listOf dnsLabel;
        default = [ ];
        example = [
          "pine"
          "cedar"
          "cherry"
          "maple"
        ];
        description = ''
          The names the convention offers.  They are handed out in list order.
          Hosts are not required to take their names from the pool.
        '';
      };
      available = derived {
        type = types.listOf types.str;
        description = "The names in `pool` that no host has taken.";
        value = lib.subtractLists (lib.attrNames cfg.hosts) cfg.hostnames.pool;
      };
    };
    networks = mkOption {
      type = types.attrsOf (types.submodule networkModule);
      default = { };
      description = ''
        The hodon's networks.  Name each after its role.  Examples are `main`
        and `guest`.  Names are lower-case DNS labels.
      '';
    };
    hosts = mkOption {
      type = types.attrsOf (types.submodule hostModule);
      default = { };
      description = ''
        Every host on the hodon.  This includes hosts the hodon does not
        build.  Names are lower-case DNS labels.
      '';
    };
  };

  options.hodix.facts.failures = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = ''
      Defects found across the hodon's facts.  Each is one message.  A module
      that extends the facts appends its own.
    '';
  };

  config = lib.mkMerge [
    { hodix.facts.failures = failures; }
    # A bare evalModules has no assertions option and rejects even a false
    # mkIf definition of one.
    (lib.optionalAttrs (options ? assertions) {
      assertions = map (message: {
        assertion = false;
        inherit message;
      }) config.hodix.facts.failures;
    })
  ];
}
