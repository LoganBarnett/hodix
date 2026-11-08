{ lib, hodix }:
let
  inherit (hodix.lib) mkHodon;

  home = {
    imports = [ ./proton.nix ];
    hodon = {
      users = {
        ada = {
          fullName = "Ada Lovelace";
          groups = [
            "family"
            "nextcloud-admins"
          ];
        };
        grace = {
          fullName = "Grace Hopper";
          groups = [
            "family"
            "nextcloud-users"
          ];
        };
      };
      groups = {
        family = { };
        nextcloud-admins.groups = [ "nextcloud-users" ];
        nextcloud-users = { };
        empty = { };
      };
    };
  };
  cycle.hodon.groups = {
    a.groups = [ "b" ];
    b.groups = [ "a" ];
  };

  hodonOf =
    extra:
    (mkHodon {
      modules = [
        home
        extra
      ];
    }).hodon;
  configOf =
    extra:
    (lib.evalModules {
      modules = [
        hodix.agnosticModules.identity
        home
        extra
      ];
    }).config;
  failuresOf = extra: (configOf extra).hodix.facts.failures;
  fails = needle: extra: lib.any (lib.hasInfix needle) (failuresOf extra);
  rejects = value: !(builtins.tryEval (builtins.deepSeq value value)).success;

  hodon = hodonOf { };
in
{
  testMembersFollowUsers = {
    expr = hodon.groups.family.members;
    expected = [
      "ada"
      "grace"
    ];
  };
  testMembersFollowGroups = {
    expr = hodon.groups.nextcloud-users.members;
    expected = [
      "ada"
      "grace"
    ];
  };
  testNestingIsOneWay = {
    expr = hodon.groups.nextcloud-admins.members;
    expected = [ "ada" ];
  };
  testMembersFollowGroupsAnyDepth = {
    expr =
      (hodonOf {
        hodon.users.linus = {
          fullName = "Linus Torvalds";
          groups = [ "staff" ];
        };
        hodon.groups.staff.groups = [ "nextcloud-admins" ];
      }).groups.nextcloud-users.members;
    expected = [
      "ada"
      "grace"
      "linus"
    ];
  };
  testEmptyGroupHasNoMembers = {
    expr = hodon.groups.empty.members;
    expected = [ ];
  };
  testUserName = {
    expr = hodon.users.ada.name;
    expected = "ada";
  };
  testNoUsersIsValid = {
    expr = (mkHodon { modules = [ ./proton.nix ]; }).hodon.groups;
    expected = { };
  };
  testGoodIdentityHasNoFailures = {
    expr = failuresOf { };
    expected = [ ];
  };
  testFactsStayPureData = {
    expr = builtins.fromJSON (builtins.toJSON hodon) == hodon;
    expected = true;
  };

  testUnknownGroupFails = {
    expr = fails "hodon.groups has no such group" {
      hodon.users.ada.groups = [ "famly" ];
    };
    expected = true;
  };
  testUnknownGroupNamesTheUser = {
    expr = fails "hodon.users.ada.groups names `famly`" {
      hodon.users.ada.groups = [ "famly" ];
    };
    expected = true;
  };
  testUnknownGroupNamesTheGroup = {
    expr = fails "hodon.groups.family.groups names `famly`" {
      hodon.groups.family.groups = [ "famly" ];
    };
    expected = true;
  };
  testCycleFails = {
    expr = fails "hodon.groups.a.groups leads back to `a`" cycle;
    expected = true;
  };
  testSelfMembershipFails = {
    expr = fails "leads back to `family`" {
      hodon.groups.family.groups = [ "family" ];
    };
    expected = true;
  };
  testCycleStillHasMembers = {
    expr = (configOf cycle).hodon.groups.a.members;
    expected = [ ];
  };
  testUserNameMustBeALabel = {
    expr = fails "hodon.users.Ada" { hodon.users.Ada.fullName = "Ada"; };
    expected = true;
  };
  testGroupNameMustBeALabel = {
    expr = fails "hodon.groups.Family" { hodon.groups.Family = { }; };
    expected = true;
  };
  testMembersCannotBeSet = {
    expr = rejects (hodonOf {
      hodon.groups.family.members = [ "ada" ];
    });
    expected = true;
  };
  testFullNameIsRequired = {
    expr = rejects (hodonOf {
      hodon.users.linus = { };
    });
    expected = true;
  };
}
