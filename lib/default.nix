{ lib, agnosticModules }:
{
  # Evaluates a hodon's facts once and outside any host.  The result's hodon
  # attribute is the validated facts.  Its module attribute carries the same
  # definitions into a host.  They appear there as config.hodon.
  mkHodon =
    { modules }:
    let
      all = agnosticModules ++ modules;
      evaluated = lib.evalModules { modules = all; };
      inherit (evaluated.config.hodix.facts) failures;
    in
    {
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
      module.imports = all;
      # The module plus the identity of the host being built.
      forHost = name: {
        imports = all;
        hodix.hostName = name;
      };
    };
}
