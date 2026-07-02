#!/bin/bash
# qemu-boot-uefi.sh — Boot the physical disk containing this script in QEMU (UEFI/OVMF)
# Debian 13. Requires: ovmf  (apt install ovmf). Launches immediately, no prompts.

# ═══════════════════════════════════════════════════════════════
#  USER CONFIG — edit if you want to change RAM / resolution
# ═══════════════════════════════════════════════════════════════
RAM_MB=4000
XRES=1920
YRES=1080
# ═══════════════════════════════════════════════════════════════

set -e

# Resolve the absolute path of this script, following symlinks
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Find the partition (source device) that holds this script
SRC_PART="$(df --output=source "$SCRIPT_DIR" | tail -n1)"

# Walk up to the parent whole-disk block device (e.g. /dev/sdb2 -> /dev/sdb, /dev/nvme0n1p1 -> /dev/nvme0n1)
PARENT_NAME="$(lsblk -no PKNAME "$SRC_PART" | head -n1)"
if [ -z "$PARENT_NAME" ]; then
    # Script is already on a whole disk (no partition)
    DISK="$SRC_PART"
else
    DISK="/dev/$PARENT_NAME"
fi

# Locate OVMF firmware (Debian 13 path)
OVMF_CODE=""
OVMF_VARS_SRC=""
for c in \
    /usr/share/OVMF/OVMF_CODE_4M.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/ovmf/OVMF.fd ; do
    [ -f "$c" ] && OVMF_CODE="$c" && break
done
for v in \
    /usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/OVMF/OVMF_VARS.fd ; do
    [ -f "$v" ] && OVMF_VARS_SRC="$v" && break
done

if [ -z "$OVMF_CODE" ] || [ -z "$OVMF_VARS_SRC" ]; then
    echo "ERROR: OVMF firmware not found. Install with: sudo apt install ovmf" >&2
    exit 1
fi

# Per-run writable copy of VARS so NVRAM edits don't clobber the system template
VARS_COPY="/tmp/qemu-ovmf-vars-$(basename "$DISK")-$$.fd"
cp "$OVMF_VARS_SRC" "$VARS_COPY"
trap 'rm -f "$VARS_COPY"' EXIT

# KVM acceleration if available
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL="-enable-kvm -cpu host"
else
    ACCEL="-cpu max"
fi

echo "Booting $DISK in QEMU (UEFI mode) with ${RAM_MB}MB RAM..."

exec sudo qemu-system-x86_64 \
    -name "UEFI-Boot-$(basename "$DISK")" \
    -m "${RAM_MB}" \
    $ACCEL \
    -smp "$(nproc)" \
    -machine type=q35,accel=kvm:tcg \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$VARS_COPY" \
    -drive file="$DISK",format=raw,if=virtio,cache=none \
    -boot order=c,menu=off \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -usb -device usb-tablet \
    -rtc base=localtime
