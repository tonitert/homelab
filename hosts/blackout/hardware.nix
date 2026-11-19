# Generic x86_64 laptop hardware: the drivers needed to find the disk at boot
# on most Intel/AMD laptops (and in QEMU for testing), plus CPU microcode and
# firmware. Replace with `nixos-generate-config --show-hardware-config` output
# from the real machine if you want it trimmed down.
{ ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";

  boot.initrd.availableKernelModules = [
    "nvme"
    "ahci"
    "xhci_pci"
    "usb_storage"
    "usbhid"
    "uas"
    "sd_mod"
    "sdhci_pci"
    "rtsx_pci_sdmmc"
    "mmc_block"
    # QEMU (tests / pxe-vm)
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
  ];
  boot.kernelModules = [
    "kvm-intel"
    "kvm-amd"
  ];

  # Serial console for `nix run .#pxe-vm -- --disk`; harmless without a serial port.
  # tty0 comes last so the laptop screen stays the main console.
  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty0"
  ];

  hardware.enableRedistributableFirmware = true; # Wi-Fi, GPU, NIC firmware
  hardware.cpu.intel.updateMicrocode = true;
  hardware.cpu.amd.updateMicrocode = true;
}
