# Applies the host's own facts to NixOS or nix-darwin.  Each value is a
# default so a host can still override it.
{ config, lib, ... }:
let
  host = config.hodix.host;
in
{
  imports = [
    ../agnostic-modules/facts.nix
    ../agnostic-modules/host.nix
  ];

  config = {
    networking.hostName = lib.mkDefault host.name;
    networking.domain = lib.mkDefault config.hodon.domain;
    nixpkgs.hostPlatform = lib.mkIf (host.system != null) (
      lib.mkDefault host.system
    );
  };
}
