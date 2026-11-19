# End-to-end installer test, no hardware needed:
#   1. UEFI firmware (OVMF) network-boots the installer exactly like the
#      laptop: DHCP+TFTP (QEMU's built-in server) -> iPXE -> netboot.ipxe ->
#      bzImage + initrd.
#   2. Runs `install-<host> --yes` onto an empty virtio disk.
#   3. Boots the installed disk and checks the system came up as expected.
# The sandbox has no network, so pulling the backend image from ghcr.io is
# the one thing this can't test.
#
# Run:  nix build .#checks.x86_64-linux.pxe-install -L
# Or run the driver directly (faster to iterate, works with less RAM):
#       PXE_TEST_MEM=2048 nix run .#checks.x86_64-linux.pxe-install.driver
{
  pkgs,
  target,
  mkInstaller,
  mkNetboot,
}:
let
  instrumentation = "${pkgs.path}/nixos/modules/testing/test-instrumentation.nix";
  tunnelId = "00000000-0000-0000-0000-000000000000";

  # linux-firmware is ~825 MB of already-compressed files, over half of the
  # installer's squashfs, and QEMU needs none of it. Without it the installer
  # initrd is ~0.7 GB instead of ~1.5 GB, so the test builds faster and fits
  # in a 2 GB VM. (The installer itself forces firmware on, hence mkOverride.)
  noFirmware.hardware.enableRedistributableFirmware = pkgs.lib.mkOverride 40 false;

  # A Git repo the test creates inside the VM. The installed system follows
  # it instead of GitHub, so the VM never rebuilds itself into the real config.
  gitopsRepo = "/var/lib/gitops-test";

  # The host as configured, plus the test driver's backdoor, a dummy tunnel
  # id (to check the tunnel waits for its credentials) and the local repo.
  testTarget = target.extendModules {
    modules = [
      instrumentation
      noFirmware
      {
        homelab.tunnel.id = pkgs.lib.mkForce tunnelId;
        homelab.gitops.flake = pkgs.lib.mkForce "git+file://${gitopsRepo}";
      }
    ];
  };
  installer = mkInstaller testTarget [
    instrumentation
    noFirmware
    # The test driver sets its own root password; drop the installer's empty one.
    { users.users.root.initialHashedPassword = pkgs.lib.mkForce null; }
  ];
  netboot = mkNetboot installer;

  inherit (testTarget.config.networking) hostName;
  inherit (testTarget.config.homelab) adminUser;
  git = "${testTarget.pkgs.gitMinimal}/bin/git"; # in the installed closure (nixos-upgrade uses it)
  qemu = "${pkgs.qemu_test}/bin/qemu-kvm -cpu max";
in
pkgs.testers.runNixOSTest {
  name = "pxe-install";
  nodes = { };
  testScript = ''
    import os
    import shutil
    import subprocess
    import tempfile

    work = tempfile.mkdtemp()
    disk = os.path.join(work, "disk.qcow2")
    efivars = os.path.join(work, "OVMF_VARS.fd")
    subprocess.run(["${pkgs.qemu_test}/bin/qemu-img", "create", "-f", "qcow2", disk, "20G"], check=True)
    shutil.copyfile("${pkgs.OVMF.variables}", efivars)
    os.chmod(efivars, 0o644)

    # RAM per VM in MiB. The installer keeps the whole system in RAM. The
    # build sandbox passes no environment, so `nix build` always uses 4096.
    mem = os.environ.get("PXE_TEST_MEM", "4096")
    base = (
        f"${qemu} -m {mem} -smp 2"
        " -drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}"
        f" -drive if=pflash,format=raw,unit=1,file={efivars}"
        f" -drive file={disk},if=virtio,format=qcow2"
    )

    with subtest("UEFI PXE boot the installer"):
        installer = create_machine(
            base
            + " -netdev user,id=net0,tftp=${netboot},bootfile=netboot.ipxe"
            + " -device virtio-net-pci,netdev=net0,romfile=${pkgs.ipxe}/ipxe.efirom,bootindex=1",
            name="installer",
        )
        installer.start()
        installer.wait_for_unit("multi-user.target")
        installer.succeed("test -d /sys/firmware/efi")
        installer.succeed("grep -q 'console=tty0' /proc/cmdline")

    with subtest("Installer refuses without confirmation"):
        installer.fail("echo no | install-${hostName} --disk /dev/vda --no-password --no-reboot")
        installer.fail("blkid /dev/vda")  # disk still untouched

    with subtest("Install onto /dev/vda"):
        installer.succeed(
            "install-${hostName} --disk /dev/vda --yes --no-password --no-reboot >&2",
            timeout=1800,
        )
        installer.succeed("test -e /mnt/boot/EFI/BOOT/BOOTX64.EFI")
        installer.succeed("test -e /mnt/boot/EFI/systemd/systemd-bootx64.efi")
        installer.succeed("readlink /mnt/nix/var/nix/profiles/system")
        installer.succeed("umount -R /mnt")
        installer.shutdown()

    with subtest("Boot the installed system from disk"):
        machine = create_machine(
            base + " -netdev user,id=net0 -device virtio-net-pci,netdev=net0",
            name="${hostName}",
        )
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("test \"$(hostname)\" = ${hostName}")
        machine.succeed("findmnt -no FSTYPE / | grep -qx ext4")
        machine.succeed("findmnt -no FSTYPE /boot | grep -qx vfat")

    with subtest("Admin access"):
        machine.wait_for_unit("sshd.service")
        machine.succeed("id -nG ${adminUser} | grep -qw wheel")
        machine.succeed("grep -q ssh-ed25519 /etc/ssh/authorized_keys.d/${adminUser}")

    with subtest("Containers and tunnel are wired up"):
        # podman tries to run the published image. The pull fails (no
        # network in the sandbox), but the error names the image.
        machine.succeed("systemctl is-enabled podman-gorilla-blackout-backend.service")
        machine.wait_until_succeeds("journalctl -u podman-gorilla-blackout-backend | grep -q ghcr.io/tonitert/gorilla-blackout-backend")
        # ... and keeps retrying every 30 s instead of hitting the start limit.
        machine.succeed("systemctl show -P StartLimitIntervalUSec podman-gorilla-blackout-backend.service | grep -qx 0")
        machine.succeed("systemctl show -P RestartUSec podman-gorilla-blackout-backend.service | grep -qx 30s")
        machine.succeed("systemctl is-enabled podman-auto-update.timer")
        # No credentials yet: the tunnel is skipped (not crash-looping) and a
        # path unit is waiting for the file to appear.
        machine.succeed("systemctl show -P ConditionResult cloudflared-tunnel-${tunnelId}.service | grep -qx no")
        machine.succeed("systemctl is-active cloudflared-tunnel-${tunnelId}-credentials.path")

    with subtest("Tailscale runs and waits for a login"):
        machine.wait_for_unit("tailscaled.service")
        machine.succeed("ip link show tailscale0")
        machine.wait_until_succeeds("tailscale status --json --peers=false | grep -q '\"BackendState\": \"NeedsLogin\"'")

    with subtest("Follows its config in Git"):
        machine.succeed("systemctl is-active nixos-upgrade.timer")
        # The repo doesn't exist yet: the check fails and nixos-rebuild never runs.
        machine.fail("systemctl start nixos-upgrade.service")
        machine.succeed("journalctl -u nixos-upgrade | grep -q 'could not get the newest commit of git+file://${gitopsRepo}'")
        machine.fail("journalctl -u nixos-upgrade | grep -q 'updating to'")
        # A commit the machine isn't running: the check passes and nixos-rebuild
        # builds <repo>#${hostName}. This flake has no nixosConfigurations, so
        # the rebuild itself fails, and the running system stays as it is.
        machine.succeed(
            "mkdir -p ${gitopsRepo} && cd ${gitopsRepo}"
            " && echo '{ outputs = _: { }; }' > flake.nix"
            " && echo '{\"nodes\":{\"root\":{}},\"root\":\"root\",\"version\":7}' > flake.lock"
            " && ${git} init -q -b main && ${git} add ."
            " && ${git} -c user.name=test -c user.email=test@test commit -qm test"
        )
        rev = machine.succeed("${git} -C ${gitopsRepo} rev-parse HEAD").strip()
        machine.fail("systemctl start nixos-upgrade.service")
        machine.succeed(f"journalctl -u nixos-upgrade | grep -q 'updating to git+file://${gitopsRepo} at {rev}'")
        machine.succeed("journalctl -u nixos-upgrade | grep -qF 'git+file://${gitopsRepo}#nixosConfigurations.\"${hostName}\"'")

    with subtest("Laptop never sleeps"):
        machine.succeed("systemctl show -P LoadState suspend.target | grep -qx masked")

    machine.shutdown()
  '';
}
