{
  lib,
  agnosticModules,
  hostModules,
  inputs,
}:
let
  # The module a peer imports to add this hodon to its hodocule.  It carries
  # only what the hodon chose to publish.
  card =
    hodon:
    if hodon.rootCertificate == null || hodon.wireguard.publicKey == null then
      throw "A card needs hodon.rootCertificate and hodon.wireguard.publicKey."
    else
      {
        hodon.hodocule.peers.${hodon.name} = {
          inherit (hodon) rootCertificate wireguard;
          groups = lib.attrNames (
            lib.filterAttrs (_: group: group.exported) hodon.groups
          );
        };
      };
  # What every host is built with, so hodix's modules find their inputs.
  hodixSpecialArgs = {
    hodix-inputs = inputs;
  };
in
{
  # Evaluates a hodon's facts once and outside any host, and configures every
  # host the facts say hodix manages.
  #
  # Only `modules` is required.  The arguments:
  #
  #   {
  #     modules;      # The facts, as a list of modules.
  #     hosts;        # A directory of `<host-name>.nix` files, or an attribute
  #                   # set of modules by host name.  Null configures no host.
  #     self;         # The flake's own `self`, for agenix-rekey and the
  #                   # default secrets directory.
  #     specialArgs;  # For the hosts' own modules, as nixosSystem takes it.
  #                   # hodix adds its own on top.
  #     nixpkgs;      # Defaults to hodix's own.
  #     nix-darwin;   # Defaults to hodix's own.
  #   }
  #
  # The result:
  #
  #   {
  #     hodon;                  # The validated facts.  Reading it fails on any
  #                             # defect and lists every one.
  #     module;                 # The facts as one module, `config.hodon` in a
  #                             # host.
  #     forHost = name: ...;    # `module` plus the host's own identity.
  #     nixosConfigurations;    # With `hosts`.  One per NixOS host.
  #     darwinConfigurations;   # With `hosts`.  One per nix-darwin host.
  #     agenix-rekey;           # With `hosts`.  Reading it needs `self`.
  #     devShells;              # With `hosts`.  Reading it needs `self`.
  #                             # Carries `agenix`, `nixos-anywhere`, and
  #                             # `hodix-install`.
  #   }
  mkHodon =
    {
      modules,
      hosts ? null,
      self ? null,
      specialArgs ? { },
      nixpkgs ? inputs.nixpkgs,
      nix-darwin ? inputs.nix-darwin,
    }:
    let
      all =
        agnosticModules
        ++ modules
        ++ lib.optional (self != null) {
          # A path, as a `./secrets` literal in the flake would be.  The
          # flake's source is already in the store, so the string context on
          # `self.outPath` adds nothing and only keeps it from becoming a path.
          hodix.secrets.directory = lib.mkDefault (
            /. + builtins.unsafeDiscardStringContext self.outPath + "/secrets"
          );
        };
      evaluated = lib.evalModules { modules = all; };
      # A path inside the flake, as the working tree spells it.
      relativeToFlake =
        path: lib.removePrefix (toString self.outPath + "/") (toString path);
      inherit (evaluated.config.hodix.facts) failures;
      hodon =
        if failures != [ ] then
          throw
            "Invalid hodon facts:\n${
              lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
            }"
        else
          # Type checks are lazy, so a malformed host stays hidden until it is
          # read.
          builtins.deepSeq evaluated.config.hodon evaluated.config.hodon;
      # The module plus the identity of the host being built.
      forHost = name: {
        imports = all;
        hodix.hostName = name;
      };
      # The hosts built for one platform, told apart by their system's suffix.
      builtFor =
        suffix:
        lib.filterAttrs (
          _: host: host.managed && lib.hasSuffix suffix host.system
        ) hodon.hosts;
      # A host's own module, either the file `<hostname>.nix` to load or the
      # module given under its name.
      hostModule =
        name:
        if lib.isAttrs hosts then
          hosts.${name} or (throw
            "`hodon.hosts.${name}` is managed, but `hosts` has no entry for it."
          )
        else
          let
            file = hosts + "/${name}.nix";
          in
          if lib.pathExists file then
            file
          else
            throw
              "`hodon.hosts.${name}` is managed, but ${
                toString file
              } does not exist.";
      configurations =
        suffix: common: build:
        lib.mapAttrs (
          name: _:
          build {
            specialArgs = specialArgs // hodixSpecialArgs;
            modules = [ (forHost name) ] ++ common ++ [ (hostModule name) ];
          }
        ) (builtFor suffix);
      nixosConfigurations =
        configurations "-linux" hostModules.nixos
          nixpkgs.lib.nixosSystem;
      darwinConfigurations =
        configurations "-darwin" hostModules.darwin
          nix-darwin.lib.darwinSystem;
    in
    {
      inherit hodon forHost;
      module.imports = all;
    }
    // lib.optionalAttrs (hosts != null) {
      inherit nixosConfigurations darwinConfigurations;
      # A flake's `self` is this very attribute set, so whether an attribute
      # exists cannot depend on it.  These two need it and say so when read.
      agenix-rekey =
        if self == null then
          throw "mkHodon needs `self` for agenix-rekey."
        else
          inputs.agenix-rekey.configure {
            userFlake = self;
            inherit nixosConfigurations darwinConfigurations;
          };
      devShells =
        if self == null then
          throw "mkHodon needs `self` for the dev shell."
        else
          lib.mapAttrs (
            system: agenix:
            let
              pkgs = nixpkgs.legacyPackages.${system};
              nixos-anywhere = inputs.nixos-anywhere.packages.${system}.default;
              install = import ./install.nix {
                inherit lib pkgs nixos-anywhere;
                agenix = agenix.default;
                secretsDirectory =
                  relativeToFlake
                    evaluated.config.hodix.secrets.directory;
                hostsDirectory =
                  if lib.isAttrs hosts then null else relativeToFlake hosts;
              };
            in
            {
              default = pkgs.mkShell {
                packages = [
                  agenix.default
                  nixos-anywhere
                  install
                ];
              };
            }
          ) inputs.agenix-rekey.packages;
    };

  inherit card;

  # A flake that calls `darwinSystem`/`nixosSystem` itself passes this as
  # `specialArgs`.
  specialArgs = hodixSpecialArgs;

  # The card as Nix source, ready to hand to a peer.
  cardText = hodon: lib.generators.toPretty { } (card hodon) + "\n";
}
