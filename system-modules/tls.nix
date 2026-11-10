# Issues the hodon's root certificate and the certificates services present
# under it, and trusts the root.  The root key never reaches a host.  Each leaf
# key is a secret of the host that presents it.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ../lib/options.nix { inherit lib; }) derived;
  cfg = config.hodix.tls;
  hodon = config.hodon;
  secrets = config.age.secrets;
  directory = config.hodix.secrets.directory;
  rootName = "root-ca";

  certificateModule =
    { name, config, ... }:
    {
      options = {
        fqdn = mkOption {
          type = types.str;
          default = name;
          defaultText = lib.literalMD "the attribute name";
          description = ''
            The name the certificate is issued for.  It is under hodon.domain,
            since the root cannot sign for anything else.
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

  inDomain =
    fqdn: fqdn == hodon.domain || lib.hasSuffix ".${hodon.domain}" fqdn;
  outside = lib.filterAttrs (
    _: certificate: !inDomain certificate.fqdn
  ) cfg.certificates;
in
{
  imports = [
    ../agnostic-modules/host.nix
    ../agnostic-modules/tls.nix
  ];

  options.hodix.tls.certificates = mkOption {
    type = types.attrsOf (types.submodule certificateModule);
    default = { };
    example = {
      "ldap.proton.hodon.internal" = { };
    };
    description = ''
      The certificates this host presents, by name.  Each is signed by the
      hodon's root.  The key is generated as a secret of this host and the
      certificate is written beside it in the repository.
    '';
  };

  config = {
    assertions = lib.mapAttrsToList (name: certificate: {
      assertion = false;
      message = "hodix.tls.certificates.${name}.fqdn is ${
        certificate.fqdn
      }, which is not under ${hodon.domain}.";
    }) outside;
    age.secrets = {
      ${rootName} = {
        intermediary = true;
        generator.script = "tls-ca-root";
        settings.tls = {
          domain = hodon.domain;
          validity = cfg.rootValidityDays;
          subject = {
            inherit (cfg.subject) country state organization;
            location = cfg.subject.locality;
            organizational-unit = cfg.subject.organizationalUnit;
          };
        };
      };
    }
    // lib.mapAttrs' (
      _: certificate:
      lib.nameValuePair certificate.keySecret {
        generator = {
          dependencies = [ secrets.${rootName} ];
          script = "tls-signed-certificate";
        };
        settings = {
          root-certificate = secrets.${rootName};
          inherit (certificate) fqdn;
        }
        // lib.optionalAttrs (certificate.validityDays != null) {
          validity = certificate.validityDays;
        };
      }
    ) cfg.certificates;
    security.pki.certificates = lib.optional (
      hodon.rootCertificate != null
    ) hodon.rootCertificate;
  };
}
