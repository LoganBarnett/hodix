# Issues the hodon's root certificate and the certificates services present
# under it, and trusts the root.  The root key never reaches a host.  Each leaf
# key is a secret of the host that presents it.
{ config, lib, ... }:
let
  cfg = config.hodix.tls;
  hodon = config.hodon;
  secrets = config.age.secrets;
  rootName = "root-ca";
  # A leaf outside the root's name constraint would be signed and then refused
  # by every client.
  inDomain =
    fqdn: fqdn == cfg.root.domain || lib.hasSuffix ".${cfg.root.domain}" fqdn;
  outside = lib.filterAttrs (
    _: certificate: !inDomain certificate.fqdn
  ) cfg.certificates;
in
{
  config = {
    assertions = lib.mapAttrsToList (name: certificate: {
      assertion = false;
      message = "hodix.tls.certificates.${name}.fqdn is ${
        certificate.fqdn
      }, which is not under ${cfg.root.domain}.";
    }) outside;
    age.secrets = {
      ${rootName} = {
        intermediary = true;
        generator.script = "tls-ca-root";
        settings.tls = cfg.root;
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
