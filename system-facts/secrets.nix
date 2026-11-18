# Turns the hodon's secrets settings and the host's own facts into agenix-rekey
# configuration.  Each value is a default so a host can still override it.
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
    # The host's SSH key.  We can set this because the installer sets it up
    # before first boot.  It doesn't need to be in the `/run/agenix` directory,
    # so we do the kludgey thing and set it as intermediary, even though it is
    # intermediary to nothing..
    age.secrets."${host.name}-ssh-host-key" = {
      generator.script = "ssh-ed25519-with-pub";
      intermediary = true;
    };
    age.rekey = lib.mkIf (cfg.directory != null) {
      storageMode = lib.mkDefault "local";
      secretsDir = lib.mkDefault (cfg.directory + "/issued");
      generatedSecretsDir = lib.mkDefault (cfg.directory + "/generated");
      localStorageDir = lib.mkDefault (cfg.directory + "/rekeyed/${host.name}");
      masterIdentities = lib.mkDefault cfg.masterIdentities;
      hostPubkey = lib.mkIf (host.sshHostKey != null) (
        lib.mkDefault (lib.trim host.sshHostKey)
      );
    };
  };
}
