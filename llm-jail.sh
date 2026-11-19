#!/usr/bin/env bash
# Start Claude Code in an llm-jail microVM with this directory as /workspace.
#
# The defaults are sized for building the PXE installer and running the
# end-to-end install test (`nix build .#checks.x86_64-linux.pxe-install`),
# which runs a nested QEMU guest and needs several GB of Nix store:
#   JAIL_MEM     guest RAM in MB                        (default 12288)
#   JAIL_VCPU    guest vCPUs                            (default 4)
#   JAIL_DISK    ext4 root disk in GB; 0 = RAM (tmpfs)  (default 30)
#   JAIL_TMPDIR  host dir for runtime data / the disk   (default: llm-jail's, ${TMPDIR:-/tmp})
#
# Examples:
#   ./llm-jail.sh                        # big jail
#   JAIL_MEM=4096 JAIL_DISK=0 ./llm-jail.sh   # the old, small jail
#   ./llm-jail.sh -- --continue          # args after `--` go to claude
set -euo pipefail

mem=${JAIL_MEM:-12288}
vcpu=${JAIL_VCPU:-4}
disk=${JAIL_DISK:-30}

args=(--dangerous --no-net-filter --mem "$mem" --vcpu "$vcpu")
if [ "$disk" != 0 ]; then
  args+=(--disk "$disk")
fi
if [ -n "${JAIL_TMPDIR:-}" ]; then
  args+=(--tmpdir "$JAIL_TMPDIR")
fi

exec nix run github:braiins/llm-jail#claude -- "${args[@]}" "$@"
