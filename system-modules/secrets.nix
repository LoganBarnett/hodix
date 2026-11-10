# Turns the hodon's secrets settings and the host's own facts into agenix-rekey
# configuration.  Each value is a default so a host can still override it.  The
# agenix, agenix-rekey, and generator modules arrive with this one through the
# flake output, since the right one depends on the class.
{ config, lib, ... }:
let
  cfg = config.hodix.secrets;
  host = config.hodix.host;
  # An intermediary secret is never encrypted to the host, so a host that holds
  # nothing else needs no key.
  holdsSecrets = lib.any (secret: !secret.intermediary) (
    lib.attrValues config.age.secrets
  );
in
{
  imports = [
    ../agnostic-modules/host.nix
    ../agnostic-modules/secrets.nix
  ];

  config = {
    assertions = [
      {
        assertion = cfg.directory != null;
        message =
          "hodix.secrets.directory is null, so the secrets module has nowhere to put anything.";
      }
      {
        assertion = !holdsSecrets || host.sshHostKey != null;
        message = "hodon.hosts.${
          host.name
        }.sshHostKey is null, so no secret can be encrypted for the host.";
      }
    ];
    age.rekey = lib.mkIf (cfg.directory != null) {
      storageMode = lib.mkDefault "local";
      secretsDir = lib.mkDefault cfg.directory;
      generatedSecretsDir = lib.mkDefault (cfg.directory + "/generated");
      localStorageDir = lib.mkDefault (cfg.directory + "/rekeyed/${host.name}");
      masterIdentities = lib.mkDefault cfg.masterIdentities;
      hostPubkey = lib.mkIf (host.sshHostKey != null) (
        lib.mkDefault (lib.trim host.sshHostKey)
      );
    };
  };
}
