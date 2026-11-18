# The dev shell command that installs a managed NixOS host from the stock NixOS
# installer.  It makes the master identity on first use, generates and rekeys
# every secret, places the host's SSH key before first boot, and hands the rest
# to nixos-anywhere.  See the Quick Start of README.org.
{
  lib,
  pkgs,
  agenix,
  nixos-anywhere,
  # Both relative to the flake root.  A null hosts directory means the flake
  # keeps its host modules inline, so no hardware configuration is written.
  secretsDirectory,
  hostsDirectory,
}:
pkgs.writeShellApplication {
  name = "hodix-install";
  runtimeInputs = [
    agenix
    nixos-anywhere
    pkgs.age
    pkgs.git
  ];
  text = ''
    if [ "$#" -lt 2 ]; then
      echo "usage: hodix-install <host> <user@address> [nixos-anywhere options]" >&2
      exit 64
    fi
    host="$1"
    target="$2"
    shift 2
    secrets=${lib.escapeShellArg secretsDirectory}
    hosts=${
      lib.escapeShellArg (if hostsDirectory == null then "" else hostsDirectory)
    }
    cd "$(git rev-parse --show-toplevel)"
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    # The master identity opens every secret.  The file sits in git, so it
    # carries a passphrase of its own.
    if [ ! -e "$secrets/master.age" ]; then
      echo "Creating the master identity at $secrets/master.age." >&2
      mkdir -p "$secrets"
      age-keygen --output "$work/identity"
      # -y prints an identity's public key.  It has no long form.
      age-keygen -y "$work/identity" > "$secrets/master.pub"
      age --passphrase --output "$secrets/master.age" "$work/identity"
      git add --intent-to-add -- "$secrets/master.age" "$secrets/master.pub"
    fi

    # Two evaluations.  The host key's public half does not exist until
    # generate has run, and rekey reads it from the facts.
    agenix generate --add-to-git
    agenix rekey --add-to-git

    # sshd finds this key on first boot and generates none, so the host
    # answers with the key its secrets are already encrypted to.
    install --directory --mode 755 "$work/extra/etc/ssh"
    agenix view "$secrets/generated/$host-ssh-host-key.age" \
      > "$work/extra/etc/ssh/ssh_host_ed25519_key"
    chmod 600 "$work/extra/etc/ssh/ssh_host_ed25519_key"
    cp "$secrets/generated/$host-ssh-host-key.pub" \
      "$work/extra/etc/ssh/ssh_host_ed25519_key.pub"

    args=()
    if [ -n "$hosts" ]; then
      args+=(--generate-hardware-config nixos-generate-config "$hosts/$host-hardware.nix")
    fi
    nixos-anywhere \
      --flake ".#$host" \
      --extra-files "$work/extra" \
      --target-host "$target" \
      "''${args[@]}" \
      "$@"
  '';
}
