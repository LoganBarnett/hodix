# The certificates a host presents under the hodon's root, as options.
# system-facts/tls.nix issues them.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ../lib/options.nix { inherit lib; }) derived;
  cfg = config.hodix.tls;
  secrets = config.age.secrets;
  directory = config.hodix.secrets.directory;

  certificateModule =
    { name, config, ... }:
    {
      options = {
        fqdn = mkOption {
          type = types.str;
          default = name;
          defaultText = lib.literalMD "the attribute name";
          description = ''
            The name the certificate is issued for.  It is under
            `hodon.internal`, since the root cannot sign for anything else.  A
            federated hodon's name is allowed, which is how a bridge answers
            for one.
          '';
        };
        validityDays = mkOption {
          type = types.nullOr types.ints.positive;
          default = cfg.certificateValidityDays;
          defaultText = lib.literalMD "hodix.tls.certificateValidityDays";
          example = 90;
          description = ''
            How long this certificate is valid, in days.  Null leaves it to
            the generator's default.
          '';
        };
        keySecret = derived {
          type = types.str;
          description = "The age.secrets entry that holds the private key.";
          value = "tls-${config.fqdn}.key";
        };
        keyFile = derived {
          type = types.str;
          description = ''
            Where the private key is decrypted on the host.  Root alone can
            read it, so a service reads it through LoadCredential.
          '';
          value = secrets.${config.keySecret}.path;
        };
        certificateFile = derived {
          type = types.path;
          description = ''
            The signed certificate in the repository.  It exists once the
            secret has been generated.
          '';
          value = directory + "/generated/tls-${config.fqdn}.crt";
        };
      };
    };
in
{
  options.hodix.tls.certificates = mkOption {
    type = types.attrsOf (types.submodule certificateModule);
    default = { };
    example = {
      "ldap.home.hodon.internal" = { };
    };
    description = ''
      The certificates this host presents, by name.  Each is signed by the
      hodon's root.  The key is generated as a secret of this host and the
      certificate is written beside it in the repository.
    '';
  };
}
