# Check specialArgs properties in order to prevent infinite recursion when
# looking up a missing DI entry.
specialArgs:
specialArgs.hodix-inputs or (throw ''
  hodix's modules read their inputs from the host's special arguments.
  Pass `specialArgs = hodix.lib.specialArgs;` to nixosSystem or darwinSystem.
'')
