# The hodon's root certificate.  Its subject is a setting of the hodon and not
# of any host, so it travels with the facts.  Once the root has been generated,
# hodon.rootCertificate defaults to it, so the card and every host trust the
# same certificate.  See the TLS section of README.org.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  directory = config.hodix.secrets.directory;
  generatedRoot =
    if directory == null then null else directory + "/generated/root-ca.crt";
in
{
  imports = [
    ./hodocule.nix
    ./secrets.nix
  ];

  options.hodix.tls = {
    subject = {
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
      locality = mkOption {
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
      organizationalUnit = mkOption {
        type = types.str;
        default = "hodon";
        description = "The root certificate's organizational unit.";
      };
    };
    rootValidityDays = mkOption {
      type = types.ints.positive;
      # Five years is a coin flip.
      default = 365 * 5;
      description = ''
        How long the root certificate is valid, in days.  Replacing the root
        means every device trusts a new one, so it is long.
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
  };

  config.hodon.rootCertificate = lib.mkDefault (
    if generatedRoot != null && builtins.pathExists generatedRoot then
      builtins.readFile generatedRoot
    else
      null
  );
}
