# Every module that works on NixOS and nix-darwin alike.
{ ... }:
{
  imports = [
    ../agnostic-modules/default.nix
    ./secrets.nix
    ./tls.nix
  ];
}
