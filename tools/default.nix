# Helper programs around the netboot files: a real PXE server for the LAN and
# a local QEMU VM that PXE-boots the installer the same way a laptop would.
{
  writeShellApplication,
  pixiecore,
  qemu_kvm,
  OVMF,
  ipxe,
  coreutils,
  netboot,
  hostName,
  adminUser,
}:
{
  pxe-server = writeShellApplication {
    name = "pxe-server";
    runtimeInputs = [
      pixiecore
      coreutils
    ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        exec sudo "$0" "$@"
      fi
      port=''${PXE_HTTP_PORT:-64172}
      cat <<EOF
      Serving the ${hostName} installer over PXE.

      pixiecore runs as a proxyDHCP server: your router keeps handing out IP
      addresses, pixiecore only adds the boot information. This machine must be
      on the same LAN segment as the laptop, with these ports open:
        UDP 67, 69, 4011 and TCP $port
      (NixOS: networking.firewall.allowedUDPPorts = [ 67 69 4011 ];
              networking.firewall.allowedTCPPorts = [ $port ];)

      Now network-boot the laptop in UEFI mode (usually F12 at power-on).
      Ctrl-C stops the server.
      EOF
      exec pixiecore boot ${netboot}/bzImage ${netboot}/initrd \
        --cmdline "$(cat ${netboot}/cmdline)" \
        --dhcp-no-bind --port "$port" --status-port "$port" "$@"
    '';
  };

  pxe-vm = writeShellApplication {
    name = "pxe-vm";
    runtimeInputs = [
      qemu_kvm
      coreutils
    ];
    text = ''
      usage() {
        cat <<EOF
      Usage: pxe-vm [--disk | --reset]

        (no args)  UEFI network boot of the ${hostName} installer, like the laptop would.
                   QEMU exits when the installer reboots.
        --disk     boot the installed system from the VM disk
        --reset    delete the VM disk and firmware variables

      State lives in \$PXE_VM_DIR (default ./.pxe-vm). RAM is \$PXE_VM_MEM MiB
      (default 4096). SSH is forwarded:
        ssh -p 2222 root@localhost (installer), ssh -p 2222 ${adminUser}@localhost (installed)
      Quit QEMU with Ctrl-A X.
      EOF
      }

      state=''${PXE_VM_DIR:-$PWD/.pxe-vm}
      mem=''${PXE_VM_MEM:-4096}
      mode=pxe
      case "''${1:-}" in
        "") ;;
        --disk) mode=disk ;;
        --reset) rm -rf "$state" && echo "removed $state" && exit 0 ;;
        -h | --help) usage && exit 0 ;;
        *) usage >&2 && exit 2 ;;
      esac

      mkdir -p "$state"
      [ -e "$state/disk.qcow2" ] || qemu-img create -q -f qcow2 "$state/disk.qcow2" 20G
      [ -e "$state/OVMF_VARS.fd" ] || install -m 644 ${OVMF.variables} "$state/OVMF_VARS.fd"

      # An empty disk makes the firmware fall through to its own PXE client,
      # which just fails with "PXE-E16: No valid offer received".
      if [ "$mode" = disk ] && ! qemu-img map --output=json "$state/disk.qcow2" | grep -q '"data": true'; then
        cat >&2 <<EOF
      Nothing is installed on $state/disk.qcow2 yet.
      Install first: nix run .#pxe-vm, press Enter, pick /dev/vda, type YES.
      QEMU exits when the install reboots; then run --disk again.
      EOF
        exit 1
      fi

      net="user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22"
      nic="virtio-net-pci,netdev=net0"
      extra=()
      if [ "$mode" = pxe ]; then
        # QEMU's built-in DHCP+TFTP plays the PXE server; the NIC's iPXE EFI
        # ROM fetches netboot.ipxe, which loads bzImage + initrd.
        net+=",tftp=${netboot},bootfile=netboot.ipxe"
        nic+=",romfile=${ipxe}/ipxe.efirom,bootindex=1"
        extra+=(-no-reboot)
      fi

      qemu-system-x86_64 \
        -machine q35 -accel kvm -accel tcg -cpu max -smp 2 -m "$mem" \
        -drive if=pflash,format=raw,unit=0,readonly=on,file=${OVMF.firmware} \
        -drive if=pflash,format=raw,unit=1,file="$state/OVMF_VARS.fd" \
        -drive file="$state/disk.qcow2",if=virtio,format=qcow2 \
        -netdev "$net" -device "$nic" \
        -nographic "''${extra[@]}"

      if [ "$mode" = pxe ]; then
        echo "VM stopped. If the install finished, boot it with: nix run .#pxe-vm -- --disk"
      fi
    '';
  };
}
