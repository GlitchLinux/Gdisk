#!/bin/bash
# qemu-boot-bios.sh — Boot the physical disk containing this script in QEMU (BIOS/SeaBIOS)
# Debian 13. Launches immediately, no prompts.

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

# KVM acceleration if available
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL="-enable-kvm -cpu host"
else
    ACCEL="-cpu max"
fi

echo "Booting $DISK in QEMU (BIOS mode) with ${RAM_MB}MB RAM..."

exec sudo qemu-system-x86_64 \
    -name "BIOS-Boot-$(basename "$DISK")" \
    -m "${RAM_MB}" \
    $ACCEL \
    -smp "$(nproc)" \
    -machine type=pc,accel=kvm:tcg \
    -drive file="$DISK",format=raw,if=virtio,cache=none \
    -boot order=c,menu=off \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -usb -device usb-tablet \
    -rtc base=localtime
