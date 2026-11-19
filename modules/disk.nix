# Single-disk layout, created by disko when the installer runs:
#   GPT -> 1 GiB EFI system partition (/boot) + ext4 root (rest of disk).
# Filesystems are mounted by partition label, so the installed system does not
# depend on whether the disk turned out to be /dev/nvme0n1, /dev/sda, ...
{ config, lib, ... }:
let
  cfg = config.homelab.disk;
in
{
  options.homelab.disk = {
    enable = lib.mkEnableOption "the standard single-disk UEFI layout" // {
      default = true;
    };
    device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/nvme0n1";
      example = "/dev/sda";
      description = ''
        Disk the installer wipes by default. The installer can also install
        to any disk listed in `homelab.installer.candidateDisks`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    disko.devices.disk.main = {
      type = "disk";
      inherit (cfg) device;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
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

    boot.loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
      };
      # Registers a boot entry so the firmware boots the disk instead of PXE
      # after install. systemd-boot also installs the removable-media
      # fallback EFI/BOOT/BOOTX64.EFI.
      efi.canTouchEfiVariables = true;
    };
  };
}
