# The nix-hapi engine, imported here alone.  Its module is a function, and the
# module system deduplicates by path, so a second import would declare its
# options twice.
{
  lib,
  pkgs,
  specialArgs,
  ...
}:
let
  hodix-inputs = import ../lib/inputs.nix specialArgs;
in
{
  imports = [ hodix-inputs.nix-hapi.nixosModules.default ];

  config.services.nix-hapi.package =
    lib.mkDefault
      hodix-inputs.nix-hapi.packages.${pkgs.stdenv.hostPlatform.system}.default;
}
