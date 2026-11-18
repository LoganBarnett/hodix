# End to end test of generating a hodon.
{
  lib,
  pkgs,
  hodix,
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  # A flake's `self.outPath` is a store path string.  The secrets directory
  # sits under it, so the manifest writes every path relative to it.
  flakeRoot = "${./.}";
  home =
    let
      result = hodix.lib.mkHodon {
        modules = [
          ./home.nix
          {
            hodon = {
              users.ada = {
                fullName = "Ada Lovelace";
                groups = [ "family" ];
              };
              groups.family = { };
            };
            hodix.tls.root.subject = {
              country = "US";
              state = "Oregon";
              location = "Portland";
            };
          }
        ];
        hosts = {
          balcony.system.stateVersion = "26.05";
          patio = { };
        };
        self = result // {
          outPath = flakeRoot;
        };
      };
    in
    result;
  secrets = home.nixosConfigurations.balcony.config.age.secrets;
  script =
    secret:
    if secret.generator == null then
      null
    else if lib.isString secret.generator then
      secret.generator
    else
      secret.generator.script;
  # The files the CLI writes passwords to, relative to the flake root the way
  # the CLI sees them.
  passwords = lib.mapAttrsToList (
    _: secret: lib.removePrefix (flakeRoot + "/") (toString secret.rekeyFile)
  ) (lib.filterAttrs (_: secret: script secret == "long-passphrase") secrets);
  tools = home.agenix-rekey.${system};
in
assert lib.assertMsg (
  passwords != [ ]
) "The fixture hodon generates no password, so there is nothing to check.";
pkgs.runCommand "generated-passwords-end-without-a-newline"
  {
    nativeBuildInputs = [
      pkgs.age
      pkgs.jq
    ];
    manifest = tools.manifest;
    generate = tools.generate;
    passwords = lib.concatStringsSep " " passwords;
  }
  ''
    mkdir hodon
    cd hodon
    export HOME="$PWD"
    # The manifest names a master identity that exists only in a real
    # repository.  A plain identity made here takes its place.
    age-keygen --output master.key
    jq --arg identity "$PWD/master.key" \
      '.masterIdentities = [ { identity: $identity, pubkey: null } ]' \
      "$manifest" > manifest.json
    # The ragenix-rekey program isn't a direct binary but a wrapper that builds
    # and supplies a `--manifest` argument.  Since we need our own manifest, we
    # need to call the binary directly with the one we built.  See
    # https://github.com/LoganBarnett/agenix-rekey/issues/1 for addressing this.
    binary=$(grep --only-matching '/nix/store/[^ ]*/bin/ragenix-rekey' \
      "$generate/bin/agenix-generate")
    "$binary" --manifest manifest.json --no-prompt generate
    status=0
    for file in $passwords; do
      age --decrypt --identity master.key "$file" > plain
      last=$(tail --bytes 1 plain | od --address-radix n --format c | tr -d ' ')
      if [ "$last" = '\n' ]; then
        echo "$file ends in a newline." >&2
        status=1
      fi
    done
    [ "$status" = 0 ]
    touch "$out"
  ''
