# PXE installer for a homelab host (`target`, a nixosSystem).
#
# It boots entirely from RAM and carries the host's complete prebuilt system,
# so installing needs no network beyond the PXE boot itself. After boot the
# console asks you to press Enter to start `install-<host>`; you can also
# SSH in as root (same keys as the admin user) and run it there.
{
  config,
  lib,
  pkgs,
  modulesPath,
  target,
  ...
}:
let
  cfg = config.homelab.installer;
  tcfg = target.config;
  hostName = tcfg.networking.hostName;
  installCmd = "install-${hostName}";

  # One disko destroy+format+mount script per candidate disk. Only the disk
  # path differs; the installed system is the same for all of them because
  # filesystems are mounted by partition label.
  diskoFor =
    dev:
    (target.extendModules { modules = [ { homelab.disk.device = lib.mkForce dev; } ]; })
    .config.system.build.destroyFormatMount;

  diskScripts = pkgs.linkFarm "${hostName}-disk-scripts" (
    map (dev: {
      name = lib.removePrefix "/dev/" dev;
      path = "${diskoFor dev}/bin/disko-destroy-format-mount";
    }) cfg.candidateDisks
  );

  installScript = pkgs.writeShellApplication {
    name = installCmd;
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      util-linux
      nixos-install-tools
    ];
    runtimeEnv = {
      TARGET_NAME = hostName;
      TOPLEVEL = "${tcfg.system.build.toplevel}";
      DISK_SCRIPTS = "${diskScripts}";
      DEFAULT_DISK = tcfg.homelab.disk.device;
      ADMIN_USER = tcfg.homelab.adminUser;
    };
    text = builtins.readFile ./install.sh;
  };
in
{
  imports = [ "${modulesPath}/installer/netboot/netboot-minimal.nix" ];

  options.homelab.installer.candidateDisks = lib.mkOption {
    type = with lib.types; listOf str;
    default = lib.unique [
      tcfg.homelab.disk.device
      "/dev/nvme0n1"
      "/dev/sda"
      "/dev/mmcblk0"
      "/dev/vda" # QEMU
    ];
    description = "Disks the installer has a partitioning script for.";
  };

  config = {
    nixpkgs.hostPlatform = target.pkgs.stdenv.hostPlatform.system;
    networking.hostName = "${hostName}-installer";
    system.stateVersion = tcfg.system.stateVersion;

    environment.systemPackages = [ installScript ];

    # Laptop NICs often need firmware. The target closure (embedded below)
    # already contains it, so this costs no extra space.
    hardware.enableRedistributableFirmware = lib.mkForce true;
    # The target uses ext4; skipping ZFS keeps the image smaller.
    boot.supportedFilesystems.zfs = lib.mkForce false;
    # No nixpkgs channel: the system to install is prebuilt and installed
    # with --no-channel-copy. Saves ~60k files of squashfs (RAM on the laptop).
    system.installer.channel.enable = false;

    # Remote access: root with the admin user's SSH keys; `ssh root@<host>-installer.local`.
    users.users.root.openssh.authorizedKeys.keys = tcfg.homelab.adminKeys;
    services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
      };
    };

    console.keyMap = tcfg.console.keyMap;
    # Serial first, tty0 last: the screen stays the primary console on a
    # laptop, and the serial port makes the installer usable in QEMU.
    boot.kernelParams = [
      "console=ttyS0,115200"
      "console=tty0"
    ];
    # Faster to build than the default level 19, slightly larger initrd.
    netboot.squashfsCompression = "zstd -Xcompression-level 6";

    # Offer the installer on the console. Waiting for Enter (instead of
    # starting right away) keeps an unattended serial getty from grabbing the
    # lock on machines where nothing is attached to ttyS0.
    services.getty.autologinUser = lib.mkForce "root";
    services.getty.helpLine = lib.mkForce "Run '${installCmd}' to install ${hostName}.";
    programs.bash.loginShellInit = ''
      if [ "$(id -u)" = 0 ]; then
        case "$(tty)" in
          /dev/tty1 | /dev/ttyS0)
            echo
            echo "  ${hostName} installer: wipes a disk and installs ${hostName}."
            echo "  Press Enter to start, or Ctrl-C for a shell (run '${installCmd}' later)."
            if read -r _; then
              flock -n /run/${installCmd}.lock ${installCmd} \
                || echo "Installer stopped (or already running on another console)."
            fi
            ;;
        esac
      fi
    '';
  };
}
