# Accepts deployments as root over SSH with the hodon's deploy key, and lets
# root in no other way.  The key is generated once for the hodon.  A managed
# workstation holds it as a secret and an unmanaged one decrypts it with the
# master identity.  Interactive sudo keeps its password, since nothing on the
# host needs it passwordless.
{ config, lib, ... }:
let
  directory = config.hodix.secrets.directory;
  publicKey = directory + "/generated/deploy-key.pub";
  generated = directory != null && builtins.pathExists publicKey;
in
{
  assertions = [
    {
      assertion = generated;
      message = ''
        The deploy key has not been generated, so root would accept no login.
        Run `agenix generate --add-to-git` and commit what it writes.
      '';
    }
  ];
  age.secrets.deploy-key = {
    generator.script = "ssh-ed25519-with-pub";
    intermediary = true;
  };
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };
  users.users.root.openssh.authorizedKeys.keys = lib.optional generated (
    lib.trim (builtins.readFile publicKey)
  );
}
