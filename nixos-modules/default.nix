# Every module a NixOS host loads.  disko is imported here alone, since no
# module of hodix's sets its options and the host's own file does.
{ specialArgs, ... }:
let
  hodix-inputs = import ../lib/inputs.nix specialArgs;
in
{
  imports = [
    hodix-inputs.disko.nixosModules.disko
    ../system-modules/default.nix
    ./ldap-server.nix
    ./nix-hapi.nix
  ];
}
