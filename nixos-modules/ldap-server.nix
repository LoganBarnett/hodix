# OpenLDAP for the hodon.  slapd answers over ldaps alone, and the nix-hapi
# LDAP provider reconciles its entries from the accounts and groups declared
# here.  Nothing is read from the facts.  nixos-facts/ldap-server.nix maps
# them onto these options.  The nix-hapi engine is nix-hapi.nix.  See
# docs/user-management.org.
{
  config,
  lib,
  pkgs,
  specialArgs,
  ...
}:
let
  inherit (lib) mkOption types;
  hodix-inputs = import ../lib/inputs.nix specialArgs;
  nixHapiLib = hodix-inputs.nix-hapi.lib;
  cfg = config.hodix.ldap.server;
  port = 636;
  adminDn = "cn=admin,${cfg.baseDn}";
  passwordSecret = name: "${name}-ldap-password";
  hashSecret = name: "${name}-ldap-password-hashed";
  credentialPath =
    name: "/run/credentials/nix-hapi-ldap.service/${hashSecret name}";
  spaces = count: lib.strings.replicate count " ";
  usersDn = "ou=users,${cfg.baseDn}";
  memberDn = uid: "uid=${uid},${usersDn}";
  withDescription =
    description:
    lib.optionalAttrs (description != null) { inherit description; };

  # slapd stores the classes it is given and the provider compares objectClass
  # as a plain attribute, so each entry declares its whole chain, top included.
  userEntries = lib.mapAttrs' (
    name: account:
    lib.nameValuePair "uid=${name}" (
      {
        objectClass = [
          "inetOrgPerson"
          "organizationalPerson"
          "person"
          "top"
        ];
        cn = account.fullName;
        sn = name;
        userPassword =
          if account.managed then
            nixHapiLib.mkManagedFromPath (credentialPath name)
          else
            nixHapiLib.mkInitialFromPath (credentialPath name);
      }
      // withDescription account.description
      // lib.optionalAttrs (account.mail != [ ]) { inherit (account) mail; }
    )
  ) cfg.accounts;
  # groupOfNames forbids an empty group, so one with no members has no entry.
  groupEntries = lib.mapAttrs' (
    name: group:
    lib.nameValuePair "cn=${name}" (
      {
        objectClass = [
          "groupOfNames"
          "top"
        ];
        member = map memberDn group.members;
      }
      // withDescription group.description
    )
  ) (lib.filterAttrs (_: group: group.members != [ ]) cfg.groups);

  accountModule =
    { name, ... }:
    {
      options = {
        fullName = mkOption {
          type = types.str;
          example = "Ada Lovelace";
          description = "The entry's common name.";
        };
        description = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "The entry's description.  Null omits the attribute.";
        };
        managed = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether the reconciler resets the password on every run.  False
            sets it on creation alone, for a person who then changes it.
          '';
        };
        group = mkOption {
          type = types.str;
          default = "root";
          description = ''
            The Unix group that may read the account's password secrets on
            this host.
          '';
        };
        mail = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "ada@example.org" ];
          description = ''
            The entry's mail addresses, the primary first.  None omits the
            attribute.
          '';
        };
      };
    };
  groupModule = {
    options = {
      description = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The group's description.  Null omits the attribute.";
      };
      members = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "The accounts in the group.";
      };
    };
  };

  # The server needs every account's hash, so each pair is declared here
  # whichever host the account belongs to.
  accountSecrets = name: account: {
    ${passwordSecret name} = {
      generator.script = "long-passphrase";
      inherit (account) group;
      shared = true;
      mode = "0440";
    };
    ${hashSecret name} = {
      generator = {
        script = "slapd-hashed";
        dependencies = [ config.age.secrets.${passwordSecret name} ];
      };
      inherit (account) group;
      shared = true;
      mode = "0440";
    };
  };
in
{
  imports = [ hodix-inputs.nix-hapi-provider-ldap.nixosModules.default ];

  options.hodix.ldap.server = {
    enable = lib.mkEnableOption "the hodon's OpenLDAP server";
    baseDn = mkOption {
      type = types.str;
      example = "dc=example,dc=org";
      description = "The suffix every entry sits under.";
    };
    fqdn = mkOption {
      type = types.str;
      example = "ldap.example.org";
      description = ''
        The name clients reach the server by.  Its certificate is issued for
        this name.
      '';
    };
    tls = {
      caCertificateFile = mkOption {
        type = types.path;
        description = ''
          The certificate of the root that signed the server's certificate.
        '';
      };
      certificateFile = mkOption {
        type = types.path;
        description = "The server's certificate.";
      };
      keyFile = mkOption {
        type = types.str;
        description = "Where the server's private key is on the host.";
      };
    };
    passwordWriteDns = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "uid=authelia-service,ou=users,dc=example,dc=org" ];
      description = "Entries allowed to write any account's userPassword.";
    };
    accounts = mkOption {
      type = types.attrsOf (types.submodule accountModule);
      default = { };
      description = "Every entry under ou=users, by uid.";
    };
    groups = mkOption {
      type = types.attrsOf (types.submodule groupModule);
      default = { };
      description = "Every entry under ou=groups, by cn.";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets = lib.mkMerge (
      [
        {
          ldap-root-pass = {
            generator.script = "long-passphrase";
            group = "openldap";
            mode = "0440";
          };
          ldap-root-pass-hashed = {
            generator = {
              script = "slapd-hashed";
              dependencies = [ config.age.secrets.ldap-root-pass ];
            };
            group = "openldap";
            mode = "0440";
          };
        }
      ]
      ++ lib.mapAttrsToList accountSecrets cfg.accounts
    );

    services.openldap = {
      enable = true;
      urlList = [
        "ldaps:///"
        "ldapi:///"
      ];
      settings = {
        attrs = {
          olcLogLevel = "acl any conns config stats stats2 trace";
          olcTLSCACertificateFile = "${cfg.tls.caCertificateFile}";
          olcTLSCertificateFile = "${cfg.tls.certificateFile}";
          olcTLSCertificateKeyFile =
            "/run/credentials/openldap.service/tls-ldap-key";
          olcTLSCipherSuite = "HIGH:MEDIUM:+3DES:+RC4:+aNULL";
          olcTLSCRLCheck = "none";
          olcTLSVerifyClient = "never";
          olcTLSProtocolMin = "3.1";
        };
        children = {
          "cn=schema".includes = [
            "${pkgs.openldap}/etc/schema/core.ldif"
            "${pkgs.openldap}/etc/schema/cosine.ldif"
            "${pkgs.openldap}/etc/schema/inetorgperson.ldif"
            "${pkgs.openldap}/etc/schema/nis.ldif"
          ];
          "cn=module{0}" = {
            attrs = {
              objectClass = [ "olcModuleList" ];
              cn = "module{0}";
              olcModuleLoad = [
                "{0}dynlist"
                "{1}back_monitor"
                "{2}ppolicy"
                "{3}memberof"
                "{4}refint"
                "{5}argon2"
              ];
            };
          };
          "olcDatabase={-1}frontend" = {
            attrs = {
              objectClass = [
                "olcDatabaseConfig"
                "olcFrontendConfig"
              ];
              olcDatabase = "{-1}frontend";
              # The hash scheme comes from a loadable module, so the setting
              # belongs to the frontend database and not to cn=config.
              olcPasswordHash = "{ARGON2}";
              olcAccess = [
                "{0}to * by dn.exact=uidNumber=0+gidNumber=0,cn=peercred,cn=external,cn=auth manage stop by * none stop"
              ];
            };
          };
          "olcDatabase={0}config" = {
            attrs = {
              objectClass = "olcDatabaseConfig";
              olcDatabase = "{0}config";
              olcAccess = [ "{0}to * by * none break" ];
            };
          };
          "olcDatabase={1}mdb" = {
            attrs = {
              objectClass = [
                "olcDatabaseConfig"
                "olcMdbConfig"
              ];
              olcDatabase = "{1}mdb";
              olcDbDirectory = "/var/lib/openldap/data";
              olcDbIndex = [
                "objectClass eq"
                "cn pres,eq"
                "uid pres,eq"
                "sn pres,eq,subany"
                "member pres,eq"
                "memberof pres,eq"
              ];
              olcSuffix = cfg.baseDn;
              olcRootDN = adminDn;
              olcRootPW.path = config.age.secrets.ldap-root-pass-hashed.path;
              # The continuation indent is cosmetic.  LDIF needs one space, and
              # the widths are arbitrary.
              olcAccess = [
                (lib.concatStringsSep "\n${spaces 20}" (
                  [
                    "{0}to attrs=userPassword"
                    "by self write"
                    "by anonymous auth"
                  ]
                  ++ map (
                    dn: ''by dn.exact="${dn}" write''
                  ) cfg.passwordWriteDns
                  ++ [ "by * none" ]
                ))
                ''{0}to * by dn.exact="${adminDn}" write by * read''
                "{1}to *\n${spaces 18}by * read"
              ];
            };

            children = {
              "olcOverlay={2}ppolicy".attrs = {
                objectClass = [
                  "olcOverlayConfig"
                  "olcPPolicyConfig"
                  "top"
                ];
                olcOverlay = "{2}ppolicy";
                olcPPolicyHashCleartext = "FALSE";
              };

              "olcOverlay={3}memberof".attrs = {
                objectClass = [
                  "olcOverlayConfig"
                  "olcMemberOf"
                  "top"
                ];
                olcOverlay = "{3}memberof";
                olcMemberOfRefInt = "TRUE";
                olcMemberOfDangling = "error";
                olcMemberOfGroupOC = "groupOfNames";
                olcMemberOfMemberAD = "member";
                olcMemberOfMemberOfAD = "memberOf";
              };

              "olcOverlay={4}refint".attrs = {
                objectClass = [
                  "olcOverlayConfig"
                  "olcRefintConfig"
                  "top"
                ];
                olcOverlay = "{4}refint";
                olcRefintAttribute = [
                  "memberof"
                  "member"
                  "manager"
                  "owner"
                ];
              };
            };
          };
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ port ];
    networking.firewall.allowedUDPPorts = [ port ];
    # Consumers order themselves after this target instead of naming
    # openldap.service, so the server can change without rewiring them.
    systemd.targets.ldap-ready = {
      description = "LDAP server is up and serving queries";
    };
    systemd.services.openldap = {
      wants = [
        "run-agenix.d.mount"
        "ldap-ready.target"
      ];
      before = [ "ldap-ready.target" ];
      # Wants and Before alone do not restart the target with the service,
      # so a runtime restart would leave consumers running against a
      # vanished server.
      requiredBy = [ "ldap-ready.target" ];
      unitConfig.PropagatesStopTo = "ldap-ready.target";
      serviceConfig.LoadCredential = [ "tls-ldap-key:${cfg.tls.keyFile}" ];
    };

    services.nix-hapi.enable = true;
    services.nix-hapi-ldap = {
      enable = true;
      servers.ldap = {
        provider = {
          url = "ldaps://${cfg.fqdn}";
          bindDn = adminDn;
          bindPassword =
            nixHapiLib.mkManagedFromPath
              "/run/credentials/nix-hapi-ldap.service/ldap-root-pass";
        };
        # The provider owns the whole naming context, so the suffix and its
        # units are declared along with what sits under them.
        entries.${cfg.baseDn} = {
          objectClass = [
            "domain"
            "top"
          ];
          entries = {
            "ou=users" = {
              objectClass = [
                "organizationalUnit"
                "top"
              ];
              entries = userEntries;
            };
            "ou=groups" = {
              objectClass = [
                "organizationalUnit"
                "top"
              ];
              entries = groupEntries;
            };
          };
        };
      };
    };

    systemd.services.nix-hapi-ldap = {
      # The reconciler connects by name and verifies the server's
      # certificate, so it needs name resolution and a corrected clock.
      # time-sync.target is passive and pulled in by its provider, so it is
      # not wanted here.
      after = [
        "openldap.service"
        "run-agenix.d.mount"
        "network-online.target"
        "nss-lookup.target"
        "time-sync.target"
      ];
      wants = [
        "openldap.service"
        "run-agenix.d.mount"
        "network-online.target"
        "nss-lookup.target"
      ];
      restartTriggers = [
        config.services.nix-hapi.jsonFiles.ldap
      ]
      ++ lib.mapAttrsToList (
        name: _: config.age.secrets.${hashSecret name}.file
      ) cfg.accounts;
      serviceConfig = {
        RemainAfterExit = true;
        LoadCredential = [
          "ldap-root-pass:${config.age.secrets.ldap-root-pass.path}"
        ]
        ++ lib.mapAttrsToList (
          name: _:
          "${hashSecret name}:${config.age.secrets.${hashSecret name}.path}"
        ) cfg.accounts;
        DynamicUser = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };
  };
}
