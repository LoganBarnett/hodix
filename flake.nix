{
  description = "Nix configuration to govern hodons.";

  inputs = {
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixfmt-strict-width = {
      url = "github:LoganBarnett/nixfmt-strict-width";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    org-fmt = {
      url = "github:LoganBarnett/org-fmt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nix-darwin,
      nixfmt-strict-width,
      nixpkgs,
      org-fmt,
    }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
      # These are paths and not imported values.  The module system can only
      # deduplicate a module imported twice when it is a path.
      agnosticModules = {
        facts = ./agnostic-modules/facts.nix;
        host = ./agnostic-modules/host.nix;
      };
      agnosticProfiles = {
        hostname-convention-periodic-table =
          ./agnostic-profiles/hostname-convention-periodic-table.nix;
        hostname-convention-wood =
          ./agnostic-profiles/hostname-convention-wood.nix;
      };
      # A system module works on NixOS and nix-darwin alike, so it is exported
      # under both classes.
      systemModules = {
        host = ./system-modules/host.nix;
      };
      darwinModules = systemModules;
      nixosModules = systemModules;
    in
    {
      inherit
        agnosticModules
        agnosticProfiles
        darwinModules
        nixosModules
        ;

      lib = import ./lib/default.nix {
        inherit lib;
        agnosticModules = lib.attrValues agnosticModules;
      };

      checks = forAllSystems (
        system:
        import ./tests/default.nix {
          inherit lib nix-darwin nixpkgs;
          pkgs = nixpkgs.legacyPackages.${system};
          hodix = self;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              # Lint GitHub Action files.
              pkgs.actionlint
              # Include a Nix formatter that uses real width instead of
              # post-indented width for width calculations.
              nixfmt-strict-width.packages.${system}.default
              # Format org-mode files.
              org-fmt.packages.${system}.default
              # Generic formatter that can handle the entire tree.
              pkgs.treefmt
            ];
          };
        }
      );
    };
}
