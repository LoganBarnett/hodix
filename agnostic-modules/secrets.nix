# Where the hodon keeps its secrets and who can open them.  These are settings
# of the hodon and not of any host, so they travel with the facts.  The system
# secrets module turns them into agenix-rekey configuration.  See the Secrets
# section of README.org.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.hodix.secrets = {
    directory = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = lib.literalExpression "./secrets";
      description = ''
        The directory of the hodon's repository that holds its secrets.  A
        hand-written secret is `<name>.age` directly inside it.  Generated
        secrets go under `generated`, and each host's rekeyed copies under
        `rekeyed/<host>`.  Write it as a path literal inside the flake, so the
        tools can place files relative to the flake root.  Null means hodix
        manages no secrets for this hodon.
      '';
    };
    masterIdentities = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            identity = mkOption {
              type = types.path;
              example = lib.literalExpression "./secrets/master.age";
              description = ''
                An age identity that can decrypt every secret in the
                repository.  Keep the file encrypted with a passphrase.
              '';
            };
            pubkey = mkOption {
              type = types.nullOr types.path;
              default = null;
              example = lib.literalExpression "./secrets/master.pub";
              description = ''
                A file holding the identity's public key.  With it, operations
                that only encrypt run without the passphrase.
              '';
            };
          };
        }
      );
      default = [ ];
      description = ''
        The identities every secret is encrypted to before any host sees it.
        Decryption tries them in order.
      '';
    };
  };
}
