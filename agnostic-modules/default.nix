# Every module that evaluates without a platform.
{ ... }:
{
  imports = [
    ./dns.nix
    ./facts.nix
    ./hodocule.nix
    ./host.nix
    ./identity.nix
    ./secrets.nix
    ./services.nix
    ./tls.nix
  ];
}
