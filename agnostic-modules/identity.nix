# Who the hodon knows.  Users name their groups, and a group names the groups
# it belongs to.  A group's members are derived from both, so membership has
# one source.  Services and peers read groups and never users.  See the Users
# and groups section of README.org.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ../lib/options.nix { inherit lib; })
    derived
    notLabel
    notLabels
    ;
  cfg = config.hodon;

  userModule =
    { name, ... }:
    {
      options = {
        name = derived {
          type = types.str;
          description = "The user's name.  It is the attribute name.";
          value = name;
        };
        fullName = mkOption {
          type = types.str;
          example = "Ada Lovelace";
          description = "The user's display name.";
        };
        groups = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "family" ];
          description = ''
            The groups the user belongs to.  Each must exist under
            hodon.groups.
          '';
        };
      };
    };

  # Every group the named group belongs to, however many steps away.  The walk
  # skips a group it has seen, so a cycle ends here and is reported below
  # instead of hanging the evaluation.
  ancestors =
    let
      go =
        seen: name:
        if lib.elem name seen then
          [ ]
        else
          let
            direct = cfg.groups.${name}.groups or [ ];
          in
          direct ++ lib.concatMap (go (seen ++ [ name ])) direct;
    in
    name: lib.unique (go [ ] name);
  belongsTo =
    user: lib.unique (user.groups ++ lib.concatMap ancestors user.groups);

  groupModule =
    { name, ... }:
    {
      options = {
        groups = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "nextcloud-users" ];
          description = ''
            The groups this group belongs to.  Its members are theirs as
            well.  Each must exist under hodon.groups.
          '';
        };
        members = derived {
          type = types.listOf types.str;
          description = ''
            Every user in the group, by name, including those who arrive
            through another group.  Membership is declared on users and
            groups, so this cannot be set.
          '';
          value = lib.attrNames (
            lib.filterAttrs (_: user: lib.elem name (belongsTo user)) cfg.users
          );
        };
      };
    };

  namesGroups =
    path: groups:
    map (
      group:
      "${path}.groups names `${group}`, and hodon.groups has no such group."
    ) (lib.filter (group: !(cfg.groups ? ${group})) groups);
  cyclic = lib.filter (name: lib.elem name (ancestors name)) (
    lib.attrNames cfg.groups
  );

  failures = lib.concatLists [
    (map (name: "hodon.users.${name}: ${notLabel name}") (
      notLabels (lib.attrNames cfg.users)
    ))
    (map (name: "hodon.groups.${name}: ${notLabel name}") (
      notLabels (lib.attrNames cfg.groups)
    ))
    (lib.concatLists (
      lib.mapAttrsToList (
        name: user: namesGroups "hodon.users.${name}" user.groups
      ) cfg.users
    ))
    (lib.concatLists (
      lib.mapAttrsToList (
        name: group: namesGroups "hodon.groups.${name}" group.groups
      ) cfg.groups
    ))
    (map (name: "hodon.groups.${name}.groups leads back to `${name}`.") cyclic)
  ];
in
{
  imports = [ ./facts.nix ];

  options.hodon = {
    users = mkOption {
      type = types.attrsOf (types.submodule userModule);
      default = { };
      example = {
        ada = {
          fullName = "Ada Lovelace";
          groups = [ "family" ];
        };
      };
      description = ''
        The hodon's users, by name.  Names are lower-case DNS labels.
      '';
    };
    groups = mkOption {
      type = types.attrsOf (types.submodule groupModule);
      default = { };
      example = {
        family = { };
        nextcloud-admins.groups = [ "nextcloud-users" ];
        nextcloud-users = { };
      };
      description = ''
        The hodon's groups.  Each maps one to one onto a directory group with
        its members flattened, so groups may nest even when the directory
        cannot.  Names are lower-case DNS labels.
      '';
    };
  };

  config.hodix.facts.failures = failures;
}
