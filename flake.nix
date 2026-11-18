{
  description = "Nix configuration to govern hodons.";

  inputs = {
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The generators take a gitAdd argument that upstream agenix-rekey gains in
    # https://github.com/oddlama/agenix-rekey/pull/165.  The fork carries it
    # until that merges.
    agenix-rekey = {
      url = "github:LoganBarnett/agenix-rekey?ref=rust-runtime";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix-rekey-generators = {
      url = "github:LoganBarnett/agenix-rekey-generators";
      inputs.nixfmt-strict-width.follows = "nixfmt-strict-width";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.org-fmt.follows = "org-fmt";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-hapi = {
      url = "github:LoganBarnett/nix-hapi";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-hapi-provider-ldap = {
      url = "github:LoganBarnett/nix-hapi-provider-ldap";
      inputs.nix-hapi.follows = "nix-hapi";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixfmt-strict-width = {
      url = "github:LoganBarnett/nixfmt-strict-width";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.disko.follows = "disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    org-fmt = {
      url = "github:LoganBarnett/org-fmt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Carries the on-demand review of a change set against the prose rules.
    rust-template = {
      url = "github:LoganBarnett/rust-template";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.org-fmt.follows = "org-fmt";
    };
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nixfmt-strict-width,
      nixpkgs,
      org-fmt,
      rust-template,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
      # Every file exported here is a path and not an imported value.  The
      # module system deduplicates a module imported twice only when it is a
      # path.  A module that needs a flake input reads it from the
      # `hodix-inputs` special argument, which `mkHodon` passes and a flake
      # managing its own hosts passes as `lib.specialArgs`.
      agnosticModules = {
        default = ./agnostic-modules/default.nix;
      };
      # Profiles are opt-in, so these are exported by name.
      agnosticProfiles = import ./agnostic-profiles/default.nix;
      # A host loads every module for its class at once.  The system modules
      # work on NixOS and nix-darwin alike, so they are Darwin's whole set.
      darwinModules = {
        default = ./system-modules/default.nix;
      };
      nixosModules = {
        default = ./nixos-modules/default.nix;
      };
      # A facts profile applies what the facts place on the host, so every
      # managed host loads all of them.  See the File Layout section of
      # docs/codebase.org.
      darwinFacts = {
        default = ./system-facts/default.nix;
      };
      nixosFacts = {
        default = ./nixos-facts/default.nix;
      };
    in
    {
      inherit
        agnosticModules
        agnosticProfiles
        darwinFacts
        darwinModules
        nixosFacts
        nixosModules
        ;

      lib = import ./lib/default.nix {
        inherit lib;
        agnosticModules = [ agnosticModules.default ];
        hostModules = {
          darwin = [
            darwinModules.default
            darwinFacts.default
          ];
          nixos = [
            nixosModules.default
            nixosFacts.default
          ];
        };
        inputs = builtins.removeAttrs inputs [ "self" ];
      };

      templates.default = {
        path = ./template;
        description = "A hodon on one machine, built from its facts.";
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
              # Review the change set against the prose rules before offering
              # it.  It drives the claude command found on PATH.
              rust-template.packages.${system}.review
            ];
          };
        }
      );
    };
}
