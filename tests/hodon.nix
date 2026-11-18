{ lib, hodix }:
let
  inherit (hodix.lib) mkHodon;

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
  };
  # What a flake would keep under hosts/, as the modules themselves.
  hosts = {
    balcony.system.stateVersion = "26.05";
    patio = { };
  };
  homeWith =
    {
      facts ? { },
      extraHosts ? { },
    }:
    mkHodon {
      modules = [
        ./home.nix
        settings
        facts
      ];
      hosts = hosts // extraHosts;
    };
  home = homeWith { };
  rejects = value: !(builtins.tryEval (builtins.deepSeq value value)).success;
in
{
  testEveryManagedHostHasAConfiguration = {
    expr = {
      nixos = lib.attrNames home.nixosConfigurations;
      darwin = lib.attrNames home.darwinConfigurations;
    };
    expected = {
      nixos = [ "balcony" ];
      darwin = [ "patio" ];
    };
  };
  testAnUnmanagedHostHasNoConfiguration = {
    expr =
      lib.attrNames
        (homeWith {
          facts.hodon.hosts.shed = {
            managed = false;
            system = "x86_64-linux";
            interfaces.main.ipv4.address = "10.10.0.10";
          };
        }).nixosConfigurations;
    expected = [ "balcony" ];
  };
  testEveryManagedHostRunsSshd = {
    expr = home.nixosConfigurations.balcony.config.services.openssh.enable;
    expected = true;
  };
  testRootLoginIsKeyOnly = {
    expr =
      home.nixosConfigurations.balcony.config.services.openssh.settings.PermitRootLogin;
    expected = "prohibit-password";
  };
  # The fixtures hold a generated deploy key.
  testRootAcceptsTheDeployKeyAlone = {
    expr =
      home.nixosConfigurations.balcony.config.users.users.root.openssh.authorizedKeys.keys;
    expected = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICOZ4r1mNCeORquPktGvu+txk5zBo62PDCRx8gzz2/XZ deploy-key"
    ];
  };
  testTheTemplateHostHasADiskLayout = {
    expr =
      (mkHodon {
        modules = [ ../template/facts.nix ];
        hosts = ../template/hosts;
        self.outPath = toString ../template;
      })
      .nixosConfigurations.balcony.config.disko.devices.disk.main.content.type;
    expected = "gpt";
  };
  testTheDefaultHostRunsTheDirectory = {
    expr = home.nixosConfigurations.balcony.config.services.openldap.enable;
    expected = true;
  };
  testAHostKnowsItself = {
    expr = home.darwinConfigurations.patio.config.networking.hostName;
    expected = "patio";
  };
  testEveryHostTrustsTheRoot = {
    expr =
      home.darwinConfigurations.patio.config.security.pki.certificates != [ ];
    expected = true;
  };
  testAMovedLdapServerLeavesTheDefaultHostAlone = {
    expr =
      (homeWith {
        facts.hodon = {
          hosts.shed = {
            system = "x86_64-linux";
            interfaces.main.ipv4.address = "10.10.0.10";
          };
          services.ldap.host = "shed";
        };
        extraHosts.shed.system.stateVersion = "26.05";
      }).nixosConfigurations.balcony.config.services.openldap.enable;
    expected = false;
  };
  testAManagedHostNeedsAModule = {
    expr = rejects (
      (homeWith { facts.hodon.hosts.barn.system = "x86_64-linux"; })
      .nixosConfigurations.barn.config.networking.hostName
    );
    expected = true;
  };
  # A flake hands mkHodon its own result as `self`, so the result's shape must
  # not depend on `self`.
  testTheWholeFlakeHasEveryOutput = {
    expr =
      let
        result = mkHodon {
          modules = [
            ./home.nix
            settings
          ];
          inherit hosts;
          self = result // {
            outPath = toString ./.;
          };
        };
      in
      lib.attrNames result;
    expected = [
      "agenix-rekey"
      "darwinConfigurations"
      "devShells"
      "forHost"
      "hodon"
      "module"
      "nixosConfigurations"
    ];
  };
  testTheDevShellNeedsSelf = {
    expr = rejects home.devShells;
    expected = true;
  };
  # The template is what nix flake init hands out, so it has to evaluate.  It
  # is also the one hosts directory the tests read.
  testTheTemplateRunsTheDirectory = {
    expr =
      (mkHodon {
        modules = [ ../template/facts.nix ];
        hosts = ../template/hosts;
        self.outPath = toString ../template;
      }).nixosConfigurations.balcony.config.services.openldap.enable;
    expected = true;
  };
  testAManagedHostNeedsAFile = {
    expr = rejects (
      (mkHodon {
        modules = [
          ../template/facts.nix
          { hodon.hosts.barn.system = "x86_64-linux"; }
        ];
        hosts = ../template/hosts;
        self.outPath = toString ../template;
      }).nixosConfigurations.barn.config.networking.hostName
    );
    expected = true;
  };
}
