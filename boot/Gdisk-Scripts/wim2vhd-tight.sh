#!/usr/bin/env bash
# wim2vhd.sh - Create bootable .vhd for each .wim file
# Each VHD: GRUB2/wimboot chainloader (BIOS+UEFI) + /sources/boot.wim
#
# Requires: qemu-utils, mtools, wget, python3, losetup, dosfstools
# Install:  sudo apt install qemu-utils mtools wget dosfstools
# Run as:   sudo ./wim2vhd.sh

set -euo pipefail

CHAINLOADER_URL="https://glitchlinux.wtf/FILES/Windows-PE/WinPE-Chainloader/WinPE-Chainloader-60MB.img"
CHAINLOADER_IMG="/tmp/WinPE-Chainloader-60MB.img"
CHAIN_PART_OFFSET=$(( 2048 * 512 ))

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Must run as root.${RESET}"; echo "Run: sudo $0"; exit 1
fi

MISSING=()
for cmd in qemu-img mcopy python3 losetup wget mkfs.fat; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${RED}Missing tools: ${MISSING[*]}${RESET}"
    echo "Install: sudo apt install qemu-utils mtools wget dosfstools"; exit 1
fi

# Download chainloader once
if [[ ! -f "$CHAINLOADER_IMG" ]]; then
    echo -e "${CYAN}Downloading chainloader image...${RESET}"
    wget -q --show-progress "$CHAINLOADER_URL" -O "$CHAINLOADER_IMG"
    echo
else
    echo -e "${GREEN}Chainloader cached: $CHAINLOADER_IMG${RESET}"
fi

CHAIN_MB=$(( $(stat -c%s "$CHAINLOADER_IMG") / 1024 / 1024 ))

# Stage chainloader files once
STAGE="/tmp/wim2vhd-chainloader-stage"
if [[ ! -d "$STAGE" ]]; then
    echo -e "${CYAN}Staging chainloader files...${RESET}"
    mkdir -p "$STAGE"
    mcopy -i "${CHAINLOADER_IMG}@@${CHAIN_PART_OFFSET}" -s -p :: "$STAGE/" 2>/dev/null
fi
STAGED_MB=$(du -sm "$STAGE" | cut -f1)
echo -e "${GREEN}Chainloader staged: ${STAGED_MB} MB${RESET}"

# Locate .wim files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIM_DIR="$SCRIPT_DIR"

shopt -s nullglob
while true; do
    wims=("$WIM_DIR"/*.wim)
    [[ ${#wims[@]} -gt 0 ]] && break
    echo -e "${YELLOW}No .wim files found in: $WIM_DIR${RESET}"
    read -rp "Enter path to directory containing .wim files: " WIM_DIR
    WIM_DIR="${WIM_DIR%/}"
    [[ -d "$WIM_DIR" ]] || { echo -e "${RED}Directory not found.${RESET}"; continue; }
done

echo -e "\n${BOLD}${CYAN}wim2vhd.sh${RESET} - Found ${BOLD}${#wims[@]}${RESET} .wim file(s) in: ${CYAN}${WIM_DIR}${RESET}\n"

SUCCESS=0; FAILED=0

for WIM in "${wims[@]}"; do
    BASENAME="$(basename "$WIM" .wim)"
    VHD="${WIM_DIR}/${BASENAME}.vhd"

    WIM_MB=$(( $(stat -c%s "$WIM") / 1024 / 1024 ))
    VHD_TOTAL_MB=$(( CHAIN_MB + WIM_MB - 13 ))

    echo -e "${BOLD}[$BASENAME]${RESET}"
    echo -e "  WIM       : ${WIM_MB} MiB"
    echo -e "  VHD total : ${VHD_TOTAL_MB} MiB"
    echo -e "  Output    : $VHD"

    # 1. Create VHD container
    qemu-img create -f vpc -o subformat=fixed "$VHD" "${VHD_TOTAL_MB}M" 2>/dev/null

    # 2. dd ENTIRE chainloader onto VHD from byte 0
    #    This flashes real MBR bootcode + partition table + full FAT32 content
    #    conv=notrunc preserves the VHD conectix footer beyond the chainloader data
    dd if="$CHAINLOADER_IMG" of="$VHD" bs=512 conv=notrunc status=none

    # 3. Extend partition table entry to fill the full VHD
    #    Read-modify-write: keep bootcode (bytes 0-445) untouched, patch size only
    python3 - "$VHD" << 'PYEOF'
import struct, sys
with open(sys.argv[1], 'r+b') as f:
    f.seek(0, 2); total = f.tell()
    disk  = total - 512       # exclude VHD footer
    start = 2048
    size  = (disk // 512) - start
    f.seek(0); mbr = bytearray(f.read(512))
    mbr[446:462] = struct.pack('<BBBBBBBBII',
        0x80, 0xFE,0xFF,0xFF, 0x0B, 0xFE,0xFF,0xFF, start, size)
    mbr[462:510] = b'\x00' * 48
    f.seek(0); f.write(mbr)
    f.seek(-512, 2)
    assert f.read(8) == b'conectix', "VHD footer lost"
PYEOF

    # 4. Mount partition region as loop device
    VHD_SIZE=$(stat -c%s "$VHD")
    PART_OFFSET=$(( 2048 * 512 ))
    PART_SIZELIMIT=$(( VHD_SIZE - 512 - PART_OFFSET ))
    LOOP=$(losetup -f --show --offset "$PART_OFFSET" --sizelimit "$PART_SIZELIMIT" "$VHD")

    # 5. Reformat FAT32 at full partition size, restore chainloader files
    mkfs.fat -F 32 -n "WINPE-BOOT" "$LOOP" 2>/dev/null
    mcopy -i "$LOOP" -s -p "$STAGE"/* :: 2>/dev/null
    echo -e "  Chainloader written"

    # 6. Mount and copy WIM directly onto partition (no /tmp)
    MNTDIR=$(mktemp -d)
    mount -t vfat -o rw "$LOOP" "$MNTDIR"
    mkdir -p "$MNTDIR/sources"
    echo -e "  Copying WIM to /sources/boot.wim..."
    cp --no-preserve=all "$WIM" "$MNTDIR/sources/boot.wim"
    sync
    umount "$MNTDIR"; rmdir "$MNTDIR"
    losetup -d "$LOOP"

    # 7. Verify footer intact
    FOOTER=$(python3 -c "
with open('$VHD','rb') as f:
    f.seek(-512,2); print(f.read(8))
")
    if [[ "$FOOTER" == "b'conectix'" ]]; then
        echo -e "  ${GREEN}OK - $(ls -lh "$VHD" | awk '{print $5}') VHD ready${RESET}"
        (( SUCCESS++ )) || true
    else
        echo -e "  ${RED}FAIL - footer corrupted${RESET}"
        (( FAILED++ )) || true
    fi
    echo
done

echo -e "${BOLD}Done.${RESET} ${GREEN}${SUCCESS} VHDs created${RESET}, ${RED}${FAILED} failed${RESET}."
echo -e "Windows: double-click .vhd | Disk Management > Attach VHD"
echo -e "Linux:   sudo losetup -fP --show file.vhd"
