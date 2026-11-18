{
  lib,
  nixpkgs,
  hodix,
}:
let
  home = hodix.lib.mkHodon {
    modules = [
      ./home.nix
      {
        hodon = {
          users = {
            ada = {
              fullName = "Ada Lovelace";
              groups = [
                "family"
                "nextcloud-admins"
              ];
            };
            barbara = {
              fullName = "Barbara Liskov";
              groups = [ "family" ];
            };
          };
          groups = {
            family = { };
            nextcloud-admins.groups = [ "nextcloud-users" ];
            nextcloud-users = { };
            nobody-yet = { };
          };
        };
      }
    ];
  };
  settings.hodix = {
    secrets = {
      # A directory on disk, since the modules read fixed paths under it.
      directory = ./fixtures/with-root;
      masterIdentities = [
        {
          identity = ./fixtures/master.age;
          pubkey = ./fixtures/master.pub;
        }
      ];
    };
    tls.root.subject = {
      country = "US";
      state = "Oregon";
      location = "Portland";
    };
    ldap.server = {
      accounts.nextcloud-service = {
        fullName = "nextcloud-service";
        description = "Nextcloud bind account.";
        group = "nextcloud";
      };
      groups.nextcloud-users.description = "People who can use Nextcloud.";
    };
  };
  nixos =
    extra:
    (nixpkgs.lib.nixosSystem {
      specialArgs = hodix.lib.specialArgs;
      modules = [
        hodix.nixosModules.default
        ../system-facts/host.nix
        ../system-facts/secrets.nix
        ../system-facts/tls.nix
        ../nixos-facts/ldap-server.nix
        (home.forHost "balcony")
        settings
        { system.stateVersion = "26.05"; }
        extra
      ];
    }).config;
  balcony = nixos { };
  # balcony under different facts, with the LDAP server placed elsewhere.
  balconyWith =
    facts:
    (nixpkgs.lib.nixosSystem {
      specialArgs = hodix.lib.specialArgs;
      modules = [
        hodix.nixosModules.default
        ../system-facts/host.nix
        ../system-facts/secrets.nix
        ../system-facts/tls.nix
        ../nixos-facts/ldap-server.nix
        (
          (hodix.lib.mkHodon {
            modules = [
              ./home.nix
              facts
            ];
          }).forHost
            "balcony"
        )
        settings
        { system.stateVersion = "26.05"; }
      ];
    }).config;
  suffix = "dc=home,dc=hodon,dc=internal";
  server = balcony.services.nix-hapi-ldap.servers.ldap;
  base = server.entries.${suffix};
  users = base.entries."ou=users".entries;
  groups = base.entries."ou=groups".entries;
  # The flattened form the reconciler is handed, keyed by DN.
  wire = balcony.services.nix-hapi.trees.ldap.desiredState.ldap.entries;
  mdb = balcony.services.openldap.settings.children."olcDatabase={1}mdb".attrs;
  # The module alone, as a hodon with its own PKI runs it.  It sees no facts.
  bare =
    (nixpkgs.lib.nixosSystem {
      specialArgs = hodix.lib.specialArgs;
      modules = [
        hodix.nixosModules.default
        ../system-facts/host.nix
        ../system-facts/secrets.nix
        (home.forHost "balcony")
        { system.stateVersion = "26.05"; }
        {
          hodix.secrets = settings.hodix.secrets;
          hodix.ldap.server = {
            enable = true;
            baseDn = "dc=example,dc=org";
            fqdn = "ldap.example.org";
            tls = {
              caCertificateFile = ./fixtures/with-root/generated/root-ca.crt;
              # The option wants a path and nothing reads the content.
              certificateFile = builtins.toFile "tls-ldap.crt" ''
                -----BEGIN CERTIFICATE-----
                ldap
                -----END CERTIFICATE-----
              '';
              keyFile = "/run/agenix/tls-ldap.example.org.key";
            };
            accounts = {
              backup-service = {
                fullName = "backup-service";
                mail = [ "backup@example.org" ];
              };
              monitor-service.fullName = "monitor-service";
            };
          };
        }
      ];
    }).config;
  bareUsers =
    bare.services.nix-hapi-ldap.servers.ldap.entries."dc=example,dc=org".entries."ou=users".entries;
in
{
  testTheProfileTurnsTheServerOn = {
    expr = balcony.services.openldap.enable;
    expected = true;
  };
  testTheSuffixComesFromTheDomain = {
    expr = mdb.olcSuffix;
    expected = suffix;
  };
  testTheAdminSitsUnderTheSuffix = {
    expr = mdb.olcRootDN;
    expected = "cn=admin,${suffix}";
  };
  testTheReconcilerBindsAsTheAdmin = {
    expr = server.provider.bindDn.value;
    expected = "cn=admin,${suffix}";
  };
  testTheSuffixAndItsUnitsAreDeclared = {
    expr = {
      suffix = base.objectClass;
      units = lib.attrNames base.entries;
    };
    expected = {
      suffix = [
        "domain"
        "top"
      ];
      units = [
        "ou=groups"
        "ou=users"
      ];
    };
  };
  testPersonsBecomeEntries = {
    expr = {
      sn = users."uid=ada".sn.value;
      cn = users."uid=ada".cn.value;
    };
    expected = {
      sn = "ada";
      cn = "Ada Lovelace";
    };
  };
  testAPersonKeepsTheirOwnPassword = {
    expr = users."uid=ada".userPassword.__nixhapi;
    expected = "initial-from-path";
  };
  testAServiceAccountsPasswordIsManaged = {
    expr = users."uid=nextcloud-service".userPassword.__nixhapi;
    expected = "managed-from-path";
  };
  testAPersonsMailIsTheirUidAtTheDomain = {
    expr = wire."uid=ada,ou=users,${suffix}".mail.value;
    expected = "ada@home.hodon.internal";
  };
  testSeveralAddressesStayAList = {
    expr =
      (nixos {
        hodix.ldap.server.accounts.ada.mail = [
          "ada@home.hodon.internal"
          "ada@example.org"
        ];
      })
      .services.nix-hapi.trees.ldap.desiredState.ldap.entries."uid=ada,ou=users,${
        suffix
      }".mail.value;
    expected = [
      "ada@example.org"
      "ada@home.hodon.internal"
    ];
  };
  testGroupMembersAreDns = {
    expr = groups."cn=nextcloud-users".member.value;
    expected = [ "uid=ada,ou=users,${suffix}" ];
  };
  testAGroupDescriptionIsCarried = {
    expr = groups."cn=nextcloud-users".description.value;
    expected = "People who can use Nextcloud.";
  };
  testAnEmptyGroupHasNoEntry = {
    expr = groups ? "cn=nobody-yet";
    expected = false;
  };
  testEveryAccountHasAPasswordHash = {
    expr =
      lib.all (name: balcony.age.secrets ? "${name}-ldap-password-hashed")
        [
          "ada"
          "barbara"
          "nextcloud-service"
        ];
    expected = true;
  };
  testTheServiceGroupReadsItsOwnSecrets = {
    expr = balcony.age.secrets."nextcloud-service-ldap-password".group;
    expected = "nextcloud";
  };
  testEveryHashReachesTheReconciler = {
    expr = lib.all (
      name:
      lib.any (lib.hasPrefix
        "${name}-ldap-password-hashed:"
      ) balcony.systemd.services.nix-hapi-ldap.serviceConfig.LoadCredential
    ) (lib.attrNames balcony.hodix.ldap.server.accounts);
    expected = true;
  };
  testTheServerCertificateIsDeclared = {
    expr = balcony.hodix.tls.certificates ? "ldap.home.hodon.internal";
    expected = true;
  };
  testTheKeyArrivesAsACredential = {
    expr = balcony.systemd.services.openldap.serviceConfig.LoadCredential;
    expected = [
      "tls-ldap-key:/run/agenix/tls-ldap.home.hodon.internal.key"
    ];
  };
  testTheReadyTargetFollowsTheServer = {
    expr = balcony.systemd.services.openldap.before;
    expected = [ "ldap-ready.target" ];
  };
  testThePortIsOpen = {
    expr = lib.elem 636 balcony.networking.firewall.allowedTCPPorts;
    expected = true;
  };
  testPasswordWritersEnterTheAcl = {
    expr = lib.any (lib.hasInfix ''by dn.exact="uid=authelia,ou=users'') (
      (nixos {
        hodix.ldap.server.passwordWriteDns = [
          "uid=authelia,ou=users,${suffix}"
        ];
      })
      .services.openldap.settings.children."olcDatabase={1}mdb".attrs.olcAccess
    );
    expected = true;
  };
  testAnotherHostRunsNoDirectory = {
    expr =
      (balconyWith {
        hodon.hosts.shed = {
          system = "x86_64-linux";
          interfaces.main.ipv4.address = "10.10.0.10";
        };
        hodon.services.ldap.host = "shed";
      }).services.openldap.enable;
    expected = false;
  };
  testAnLdapServerKeptByHandRunsNowhere = {
    expr =
      (balconyWith {
        hodon.services.ldap = {
          enable = false;
          host = "printer";
        };
      }).services.openldap.enable;
    expected = false;
  };
  testTheModuleReadsNoFacts = {
    expr = lib.attrNames bareUsers;
    expected = [
      "uid=backup-service"
      "uid=monitor-service"
    ];
  };
  testAServiceAccountsMailIsCarried = {
    expr = bareUsers."uid=backup-service".mail.value;
    expected = [ "backup@example.org" ];
  };
  testAnAccountWithoutMailHasNone = {
    expr = bareUsers."uid=monitor-service" ? mail;
    expected = false;
  };
  testAnotherPkiSuppliesItsOwnFiles = {
    expr = {
      suffix =
        bare.services.openldap.settings.children."olcDatabase={1}mdb".attrs.olcSuffix;
      key = bare.services.openldap.settings.attrs.olcTLSCertificateKeyFile;
      ca =
        lib.hasSuffix "root-ca.crt"
          bare.services.openldap.settings.attrs.olcTLSCACertificateFile;
    };
    expected = {
      suffix = "dc=example,dc=org";
      key = "/run/credentials/openldap.service/tls-ldap-key";
      ca = true;
    };
  };
  testTheLdapServerDeclaresItsAlias = {
    expr = balcony.hodix.dns.aliases;
    expected = {
      ldap = "balcony";
    };
  };
  # A hodon without the service has no name for it either.
  testAnAbsentLdapServerDeclaresNoAlias = {
    expr = (nixos { hodon.services.ldap.enable = false; }).hodix.dns.aliases;
    expected = { };
  };
}
