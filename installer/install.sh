# install-<host>: wipe a disk and install the prebuilt NixOS system on it.
# Wrapped by writeShellApplication (strict mode, shellcheck) in netboot.nix,
# which also sets TARGET_NAME, TOPLEVEL, DISK_SCRIPTS, DEFAULT_DISK and ADMIN_USER.

usage() {
  cat <<USAGE
Usage: install-$TARGET_NAME [--disk DEVICE] [--yes] [--no-password] [--no-reboot]

Wipes DEVICE, creates an EFI system partition + ext4 root and installs $TARGET_NAME.

  --disk DEVICE   disk to install to (default: $DEFAULT_DISK if it exists, else ask)
  --yes           don't ask before wiping the disk
  --no-password   don't ask for a console password for $ADMIN_USER
  --no-reboot     leave the new system mounted at /mnt instead of rebooting
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

disk=""
assume_yes=0
set_password=1
do_reboot=1
while [ $# -gt 0 ]; do
  case "$1" in
    --disk)
      [ $# -ge 2 ] || die "--disk needs a device"
      disk=$2
      shift 2
      ;;
    --yes) assume_yes=1 && shift ;;
    --no-password) set_password=0 && shift ;;
    --no-reboot) do_reboot=0 && shift ;;
    -h | --help) usage && exit 0 ;;
    *) usage >&2 && exit 2 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "run as root"
[ -d /sys/firmware/efi ] ||
  die "this machine booted in legacy BIOS mode, but $TARGET_NAME needs UEFI. Switch the firmware to UEFI network boot and PXE boot again."

prepared=$(cd "$DISK_SCRIPTS" && echo *)

echo
echo "=== Installing $TARGET_NAME"
echo "    $TOPLEVEL"
echo
lsblk --nodeps -e 1,7,11 -o NAME,SIZE,TYPE,TRAN,MODEL
echo

if [ -z "$disk" ]; then
  if [ -b "$DEFAULT_DISK" ]; then
    disk=$DEFAULT_DISK
  elif [ "$assume_yes" -eq 1 ]; then
    die "$DEFAULT_DISK does not exist; pass --disk"
  else
    read -rp "Install to which disk? [$prepared]: " disk
  fi
fi
disk=/dev/${disk#/dev/}
name=${disk#/dev/}
[ -x "$DISK_SCRIPTS/$name" ] ||
  die "no partitioning script for $disk (have: $prepared). Add it to homelab.installer.candidateDisks."
[ -b "$disk" ] || die "$disk is not a block device"

if [ "$assume_yes" -ne 1 ]; then
  echo "!!! ALL DATA ON $disk ($(lsblk --nodeps -no SIZE,MODEL "$disk" | xargs)) WILL BE DESTROYED !!!"
  read -rp "Type YES to continue: " answer
  [ "$answer" = YES ] || die "aborted, nothing was changed"
fi

echo "=== Partitioning and formatting $disk"
"$DISK_SCRIPTS/$name" --yes-wipe-all-disks

echo "=== Copying system to disk and installing the bootloader"
nixos-install --system "$TOPLEVEL" --no-root-passwd --no-channel-copy

if [ "$set_password" -eq 1 ]; then
  echo "=== Console password for $ADMIN_USER (SSH logins use keys only)"
  until nixos-enter --root /mnt -c "passwd $ADMIN_USER"; do
    echo "Try again."
  done
fi

echo "=== $TARGET_NAME installed on $disk"
if [ "$do_reboot" -eq 1 ]; then
  umount -R /mnt
  echo "Rebooting in 5 seconds (Ctrl-C to stay in the installer)..."
  sleep 5
  systemctl reboot
else
  echo "The new system is still mounted at /mnt."
fi
