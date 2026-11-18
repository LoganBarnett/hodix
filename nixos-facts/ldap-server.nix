# The facts layer for the LDAP server.  Converts `hodon.users` and
# `hodon.groups` into the accounts and groups.  See docs/user-management.org.
{ config, lib, ... }:
let
  inherit (config) hodon;
  ldap = hodon.services.ldap;
  here = ldap.enable && ldap.host == config.hodix.hostName;
  cfg = config.hodix.ldap.server;
  certificate = config.hodix.tls.certificates.${cfg.fqdn};
in
{
  # Declared on every host, so the one serving DNS answers for it.
  hodix.dns.aliases = lib.mkIf ldap.enable { ldap = ldap.host; };
  hodix.ldap.server = lib.mkIf here {
    enable = true;
    baseDn = lib.mkDefault (
      lib.concatMapStringsSep "," (label: "dc=${label}") (
        lib.splitString "." hodon.domain
      )
    );
    fqdn = lib.mkDefault "ldap.${hodon.domain}";
    accounts = lib.mapAttrs (name: user: {
      inherit (user) fullName;
      managed = false;
      mail = lib.mkDefault [ "${name}@${hodon.domain}" ];
    }) hodon.users;
    groups = lib.mapAttrs (_: group: {
      inherit (group) members;
    }) hodon.groups;
    tls = {
      caCertificateFile = lib.mkDefault config.hodix.tls.rootCertificateFile;
      certificateFile = lib.mkDefault certificate.certificateFile;
      keyFile = lib.mkDefault certificate.keyFile;
    };
  };
  hodix.tls.certificates = lib.mkIf here { ${cfg.fqdn} = { }; };
}
