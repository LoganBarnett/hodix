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
      agenix,
      agenix-rekey,
      agenix-rekey-generators,
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
        hodocule = ./agnostic-modules/hodocule.nix;
        host = ./agnostic-modules/host.nix;
        identity = ./agnostic-modules/identity.nix;
        secrets = ./agnostic-modules/secrets.nix;
        tls = ./agnostic-modules/tls.nix;
      };
      agnosticProfiles = {
        hostname-convention-bean =
          ./agnostic-profiles/hostname-convention-bean.nix;
        hostname-convention-periodic-table =
          ./agnostic-profiles/hostname-convention-periodic-table.nix;
        hostname-convention-petal =
          ./agnostic-profiles/hostname-convention-petal.nix;
        hostname-convention-wood =
          ./agnostic-profiles/hostname-convention-wood.nix;
      };
      # A system module works on NixOS and nix-darwin alike, so it is exported
      # under both classes.
      systemModules = {
        host = ./system-modules/host.nix;
      };
      # The secrets module brings agenix, agenix-rekey, and the generators with
      # it, each for the class it is imported into.  A fixed key lets the
      # module system drop the copy that tls imports when a host imports both.
      secretsModule = class: {
        key = "hodix/secrets";
        _file = "hodix/${class}Modules.secrets";
        imports = [
          agenix."${class}Modules".default
          agenix-rekey."${class}Modules".default
          agenix-rekey-generators."${class}Modules".default
          ./system-modules/secrets.nix
        ];
      };
      tlsModule = class: {
        key = "hodix/tls";
        _file = "hodix/${class}Modules.tls";
        imports = [
          (secretsModule class)
          ./system-modules/tls.nix
        ];
      };
      modulesFor =
        class:
        systemModules
        // {
          secrets = secretsModule class;
          tls = tlsModule class;
        };
      darwinModules = modulesFor "darwin";
      nixosModules = modulesFor "nixos";
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
