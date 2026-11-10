{
  lib,
  nix-darwin,
  nixpkgs,
  pkgs,
  hodix,
}:
let
  # A failing suite stops evaluation, so the failed cases print without a
  # build log to dig through.
  suite =
    name: cases:
    let
      failed = lib.runTests cases;
    in
    if failed == [ ] then
      pkgs.emptyFile
    else
      throw "${name} tests failed:\n${lib.generators.toPretty { } failed}";
in
{
  facts = suite "facts" (import ./facts.nix { inherit lib hodix; });
  hodocule = suite "hodocule" (import ./hodocule.nix { inherit lib hodix; });
  identity = suite "identity" (import ./identity.nix { inherit lib hodix; });
  ipv4 = suite "ipv4" (import ./ipv4.nix { inherit lib; });
  nixos = suite "nixos" (import ./nixos.nix { inherit lib nixpkgs hodix; });
  darwin = suite "darwin" (
    import ./darwin.nix { inherit lib nix-darwin hodix; }
  );
  secrets = suite "secrets" (
    import ./secrets.nix {
      inherit
        lib
        nix-darwin
        nixpkgs
        hodix
        ;
    }
  );
  tls = suite "tls" (
    import ./tls.nix {
      inherit
        lib
        nix-darwin
        nixpkgs
        hodix
        ;
    }
  );
}
