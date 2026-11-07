# Facts describe every host, so a configuration has to be told which entry is
# its own.  That identity is not a fact.  It differs per evaluation.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  name = config.hodix.hostName;
in
{
  options.hodix = {
    hostName = mkOption {
      type = types.str;
      example = "silicon";
      description = ''
        The `hodon.hosts` entry this configuration builds.
      '';
    };
    host = mkOption {
      type = types.raw;
      readOnly = true;
      default =
        config.hodon.hosts.${name} or (throw
          "hodix.hostName names `${name}`, which is not in hodon.hosts."
        );
      defaultText = lib.literalMD "derived";
      description = ''
        The facts of the host this configuration builds.
      '';
    };
  };
}
