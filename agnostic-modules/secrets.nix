# Where the hodon keeps its secrets and who can open them.  These are settings
# of the hodon and not of any host, so they travel with the facts.  The system
# secrets module turns them into agenix-rekey configuration.  See the Secrets
# section of docs/codebase.org.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.hodix.secrets;
  # agenix-rekey reads a pubkey given as a path and takes a string as the key
  # itself, so this is a path whatever the directory was written as.
  masterPubkey = /. + toString cfg.directory + "/master.pub";
in
{
  options.hodix.secrets = {
    directory = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = lib.literalExpression "./secrets";
      description = ''
        The directory of the hodon's repository that holds its secrets.
        `mkHodon` defaults it to `secrets` under the flake root when it is
        given `self`.  A hand-written secret is `issued/<name>.age` inside it.
        Generated secrets go under `generated`, and each host's rekeyed copies
        under `rekeyed/<host>`.  Write hand written secrets as a path literal
        inside the flake, so the tools can place files relative to the flake
        root.  Null means hodix manages no secrets for this hodon.
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
      default = lib.optional (cfg.directory != null) {
        identity = cfg.directory + "/master.age";
        # The public key exists once the identity has been made, and null
        # only costs the passphrase prompt until then.
        pubkey =
          if builtins.pathExists masterPubkey then masterPubkey else null;
      };
      defaultText =
        lib.literalMD
          "`master.age` and `master.pub` in the secrets directory";
      description = ''
        The identities every secret is encrypted to before any host sees it.
        Decryption tries them in order.
      '';
    };
  };
}
