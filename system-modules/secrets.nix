# The agenix, agenix-rekey, and generator modules are imported here alone.  This
# is because imported modules from Flake inputs are functions.  Functions don't
# enjoy deduplication by the module system, so the module winds up getting
# imported twice and causing an error.
{ _class, specialArgs, ... }:
let
  hodix-inputs = import ../lib/inputs.nix specialArgs;
in
{
  imports = [
    hodix-inputs.agenix."${_class}Modules".default
    hodix-inputs.agenix-rekey."${_class}Modules".default
    hodix-inputs.agenix-rekey-generators."${_class}Modules".default
  ];
}
