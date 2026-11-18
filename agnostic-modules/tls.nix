# The hodon's root certificate.  Its settings are the hodon's and not any
# host's, so they travel with the facts.  Once the root has been generated,
# hodon.rootCertificate defaults to it, so the card and every host trust the
# same certificate.  See the TLS section of docs/codebase.org.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ../lib/options.nix { inherit lib; }) derived internalDomain;
  directory = config.hodix.secrets.directory;
  generatedRoot =
    if directory == null then null else directory + "/generated/root-ca.crt";
  # The keys are the generator's own, so a key it learns to read can be set
  # without hodix knowing it.
  freeform = types.attrsOf types.anything;
  subjectModule.options = {
    country = mkOption {
      type = types.strMatching "[A-Z]{2}";
      example = "US";
      description = "The root certificate's country, as a two-letter code.";
    };
    state = mkOption {
      type = types.str;
      example = "Oregon";
      description = "The root certificate's state or province.";
    };
    location = mkOption {
      type = types.str;
      example = "Portland";
      description = "The root certificate's city or town.";
    };
    organization = mkOption {
      type = types.str;
      default = config.hodon.name;
      defaultText = lib.literalMD "the hodon's name";
      description = "The root certificate's organization.";
    };
    organizational-unit = mkOption {
      type = types.str;
      default = "hodon";
      description = "The root certificate's organizational unit.";
    };
  };
  rootModule.options = {
    domain = mkOption {
      type = types.str;
      default = internalDomain;
      description = ''
        The names the root may sign for.  Every hodon's names by default, so
        a bridge on this hodon can answer for a federated one.
      '';
    };
    validity = mkOption {
      type = types.ints.positive;
      # Five years is a coin flip.
      default = 365 * 5;
      description = ''
        How long the root certificate is valid, in days.  Replacing the root
        means every device trusts a new one, so it is long.
      '';
    };
    subject = mkOption {
      type = types.submodule {
        freeformType = freeform;
        imports = [ subjectModule ];
      };
      default = { };
      description = "The root certificate's subject.";
    };
  };
in
{
  imports = [
    ./hodocule.nix
    ./secrets.nix
  ];

  options.hodix.tls = {
    root = mkOption {
      type = types.submodule {
        freeformType = freeform;
        imports = [ rootModule ];
      };
      default = { };
      example = {
        subject = {
          country = "US";
          state = "Oregon";
          location = "Portland";
        };
      };
      description = ''
        The root certificate's generator settings, handed to `tls-ca-root` as
        `settings.tls`.  hodix fills in what it knows and passes the rest
        through untouched.
      '';
    };
    certificateValidityDays = mkOption {
      type = types.nullOr types.ints.positive;
      default = null;
      example = 90;
      description = ''
        How long a service's certificate is valid, in days, unless the
        certificate sets its own.  Null leaves it to the generator's default.
      '';
    };
    rootCertificateFile = derived {
      type = types.nullOr types.path;
      description = ''
        The root's certificate in the repository, for a service that needs a
        file.  It exists once the root has been generated.  Null until
        `hodix.secrets.directory` is set.
      '';
      value = generatedRoot;
    };
  };

  config.hodon.rootCertificate = lib.mkDefault (
    if generatedRoot != null && builtins.pathExists generatedRoot then
      builtins.readFile generatedRoot
    else
      null
  );
}
