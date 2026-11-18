# Every facts profile that applies on NixOS and nix-darwin alike.
{ ... }:
{
  imports = [
    ./host.nix
    ./secrets.nix
    ./tls.nix
  ];
}
