# The default host's hardware and boot.  Nothing about hodix belongs here.
{ lib, ... }:
{
  # hodix-install writes this file from the running installer, so it does not
  # exist until the first install.
  imports = lib.optional (builtins.pathExists
    ./balcony-hardware.nix
  ) ./balcony-hardware.nix;
  # The machine boots with UEFI.  A BIOS machine takes GRUB in its place.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # The whole disk becomes a boot partition and one root filesystem.  Put the
  # disk's stable name from /dev/disk/by-id in device.
  disko.devices.disk.main = {
    device = "/dev/disk/by-id/some-disk-id";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "500M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
  system.stateVersion = "26.05";
}
