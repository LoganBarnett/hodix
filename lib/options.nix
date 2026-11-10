# Option types and helpers shared by the agnostic modules.
{ lib }:
let
  inherit (lib) mkOption types;
  labelPattern = "[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?";
  isLabel = name: builtins.match labelPattern name != null;
  pemBegin = "-----BEGIN CERTIFICATE-----";
  pemEnd = "-----END CERTIFICATE-----";
in
{
  inherit isLabel;
  dnsLabel = types.strMatching labelPattern;
  notLabel = name: "`${name}` is not a lower-case DNS label.";
  notLabels = names: lib.filter (name: !isLabel name) names;

  # Option documentation is generated without a configured hodon.  The fixed
  # defaultText keeps it from forcing the value.
  derived =
    {
      type,
      description,
      value,
    }:
    mkOption {
      inherit type description;
      readOnly = true;
      default = value;
      defaultText = lib.literalMD "derived";
    };

  # Nix cannot parse X.509, so this checks the framing and nothing more.
  pemCertificate = lib.mkOptionType {
    name = "pemCertificate";
    description = "one PEM encoded X.509 certificate";
    descriptionClass = "noun";
    check =
      value:
      lib.isString value
      && lib.hasPrefix pemBegin (lib.trim value)
      && lib.hasSuffix pemEnd (lib.trim value)
      && lib.length (lib.splitString pemBegin value) == 2;
    merge = lib.mergeEqualOption;
  };
  wireguardKey = lib.mkOptionType {
    name = "wireguardKey";
    description = "WireGuard public key, 32 bytes in base64";
    descriptionClass = "noun";
    check =
      value:
      lib.isString value && builtins.match "[A-Za-z0-9+/]{43}=" value != null;
    merge = lib.mergeEqualOption;
  };
  wireguardEndpoint = lib.mkOptionType {
    name = "wireguardEndpoint";
    description = "host:port, with an IPv6 host in brackets";
    descriptionClass = "noun";
    check =
      value:
      lib.isString value
      &&
        builtins.match "(\\[[0-9a-fA-F:.]+]|[A-Za-z0-9.-]+):[0-9]{1,5}" value
        != null;
    merge = lib.mergeEqualOption;
  };
  # An ed25519 key is always 68 base64 characters, so the pattern is exact.  A
  # comment and a trailing newline are allowed, since the text usually comes
  # straight from a .pub file.
  sshEd25519PublicKey = lib.mkOptionType {
    name = "sshEd25519PublicKey";
    description = "OpenSSH ed25519 public key, as written in a .pub file";
    descriptionClass = "noun";
    check =
      value:
      lib.isString value
      &&
        builtins.match
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]{43}( [^\n]*)?\n?"
          value != null;
    merge = lib.mergeEqualOption;
  };
}
