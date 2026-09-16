#!/bin/bash
# ====================================================================
#  mkiso-custom.sh  -  Gdisk v3.0 ISO Compiler
# --------------------------------------------------------------------
#  Builds a hybrid bootable ISO from a Gdisk source directory.
#  Uses patched GRUB2 for both BIOS and UEFI boot.
#
#  BIOS boot: cdboot.img + core-patched.img El Torito
#             boot_hybrid.img MBR for USB isohybrid
#  UEFI boot: 4MB FAT12 efi.img with EFI/BOOT/BOOTX64.EFI
#             GPT EFI System Partition for USB isohybrid
#
#  The resulting ISO can be:
#    - Burned to CD/DVD (BIOS + UEFI)
#    - Written to USB with Rufus, Etcher, dd, PowerISO (BIOS + UEFI)
#    - Mounted as virtual CD in QEMU/VirtualBox/VMware
#    - Used as a Gdisk install medium on Windows
#
#  Usage:
#    sudo bash gdisk-mkiso.sh
#    sudo bash gdisk-mkiso.sh /path/to/source /path/to/output.iso
#
#  Dependencies: xorriso, dosfstools, grub-pc-bin
#
#  Source: https://github.com/GlitchLinux/Gdisk.git
#  License: GPLv3
# ====================================================================

set -euo pipefail

export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"

# -------------------- config --------------------
ISO_LABEL="Gdisk-v3"
# BUILD_DIR and EFI_MNT are set after output path is known (Step 2)

# -------------------- styling --------------------
RED=$'\e[0;31m'; GRN=$'\e[0;32m'; YLW=$'\e[1;33m'
CYN=$'\e[0;36m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; NC=$'\e[0m'
MAGENTA=$'\033[38;5;198m'

HL="$MAGENTA"
RULE_COLOR="$DIM$CYN"

rule() {
    local w; w="$(tput cols 2>/dev/null || echo 60)"
    [ "$w" -gt 70 ] && w=70
    printf "${RULE_COLOR}%*s${NC}\n" "$w" '' | tr ' ' '-'
}

msg()  { echo -e "${GRN}[+]${NC} $*"; }
warn() { echo -e "${YLW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; }
info() { echo -e "${CYN}[i]${NC} $*"; }
die()  { err "$*"; cleanup; exit 1; }

cleanup() {
    [[ -n "${EFI_MNT:-}" ]] && mountpoint -q "$EFI_MNT" 2>/dev/null && umount "$EFI_MNT" 2>/dev/null
    [[ -n "${BUILD_DIR:-}" ]] && rm -rf "$BUILD_DIR" 2>/dev/null
    [[ -n "${EFI_MNT:-}" ]] && rm -rf "$EFI_MNT" 2>/dev/null
}
trap cleanup EXIT

# -------------------- banner --------------------
clear
echo
echo "${CYN} ${BOLD}Gdisk v3.0${NC} ❖${NC}${CYN} ${BOLD}ISO Compiler${NC}"
echo
rule

# -------------------- root --------------------
[ "$(id -u)" -eq 0 ] || die "Run as root:  sudo $0"

# -------------------- dependency check --------------------
need() {
    local t found
    for t in "$@"; do
        found=0
        for p in "$t" "/sbin/$t" "/usr/sbin/$t" "/usr/local/sbin/$t"; do
            command -v "$p" >/dev/null 2>&1 && { found=1; break; }
        done
        if [ "$found" -eq 0 ]; then
            case "$t" in
                xorriso)    die "missing: xorriso - install with: apt install xorriso" ;;
                mkfs.vfat)  die "missing: mkfs.vfat - install with: apt install dosfstools" ;;
                *)          die "missing required tool: $t" ;;
            esac
        fi
    done
}
need xorriso mkfs.vfat rsync

# ====================================================================
#  Step 1: Get Gdisk source directory
# ====================================================================
echo
if [[ -n "${1:-}" ]]; then
    GDISK_SRC="$1"
else
    info "Enter path to Gdisk source directory"
    info "  This should contain boot/grub/, EFI/BOOT/, and grub.cfg"
    echo
    read -rp "$(echo -e "${CYN}Gdisk source directory: ${NC}")" GDISK_SRC
fi

GDISK_SRC="$(realpath -e "$GDISK_SRC" 2>/dev/null)" || die "Directory does not exist: ${GDISK_SRC:-<empty>}"
[[ -d "$GDISK_SRC" ]] || die "Not a directory: $GDISK_SRC"
[[ "$(ls -A "$GDISK_SRC")" ]] || die "Directory is empty: $GDISK_SRC"

msg "Source: ${HL}$GDISK_SRC${NC}"

# ====================================================================
#  Step 2: Get ISO output path
# ====================================================================
DEFAULT_OUTPUT="$(dirname "$GDISK_SRC")/Gdisk-v3.iso"

if [[ -n "${2:-}" ]]; then
    ISO_OUTPUT="$2"
else
    echo
    read -rp "$(echo -e "${CYN}ISO output path [${DEFAULT_OUTPUT}]: ${NC}")" ISO_OUTPUT
    ISO_OUTPUT="${ISO_OUTPUT:-$DEFAULT_OUTPUT}"
fi

# Resolve parent directory (output file may not exist yet)
ISO_OUTPUT_DIR="$(dirname "$ISO_OUTPUT")"
ISO_OUTPUT_DIR="$(realpath -e "$ISO_OUTPUT_DIR" 2>/dev/null)" || die "Output directory does not exist: $(dirname "$ISO_OUTPUT")"
ISO_OUTPUT="${ISO_OUTPUT_DIR}/$(basename "$ISO_OUTPUT")"

# Conflict check
if [[ -f "$ISO_OUTPUT" ]]; then
    warn "File already exists: $ISO_OUTPUT"
    read -rp "$(echo -e "${YLW}Overwrite? [y/N]: ${NC}")" confirm
    [[ "${confirm,,}" == "y" ]] || { info "Aborted."; exit 0; }
    rm -f "$ISO_OUTPUT"
fi

# Set build dirs in same parent as output (avoids tmpfs/RAM pressure)
BUILD_DIR="${ISO_OUTPUT_DIR}/.gdisk-mkiso-build-$$"
EFI_MNT="${ISO_OUTPUT_DIR}/.gdisk-mkiso-efimnt-$$"

msg "Output: ${HL}$ISO_OUTPUT${NC}"

# ====================================================================
#  Step 3: Validate critical files
# ====================================================================
echo
msg "Validating source structure..."

[ -f "$GDISK_SRC/boot/grub/i386-pc/core-patched.img" ] || die "Source missing: boot/grub/i386-pc/core-patched.img"
[ -f "$GDISK_SRC/EFI/BOOT/BOOTX64.EFI" ]               || die "Source missing: EFI/BOOT/BOOTX64.EFI"
[ -f "$GDISK_SRC/boot/grub/grub.cfg" ]                  || die "Source missing: boot/grub/grub.cfg"

msg "Source structure validated"

# ====================================================================
#  Step 4: Locate GRUB boot images
# ====================================================================
CDBOOT_SYS="/usr/lib/grub/i386-pc/cdboot.img"
HYBRID_MBR="/usr/lib/grub/i386-pc/boot_hybrid.img"

if [ ! -f "$CDBOOT_SYS" ] || [ ! -f "$HYBRID_MBR" ]; then
    warn "GRUB i386-pc boot images not found"
    info "Installing grub-pc-bin..."
    apt-get install -y grub-pc-bin 2>/dev/null || true
    [ -f "$CDBOOT_SYS" ] || die "cdboot.img not found - install grub-pc-bin"
    [ -f "$HYBRID_MBR" ] || die "boot_hybrid.img not found - install grub-pc-bin"
fi

# ====================================================================
#  Step 5: Prepare ISO staging directory
# ====================================================================
msg "Preparing ISO staging area..."
mkdir -p "$BUILD_DIR/iso"

rsync -a --exclude='.git' --exclude='.gitignore' --exclude='.gitattributes' \
      "$GDISK_SRC"/ "$BUILD_DIR/iso"/ \
    || die "rsync failed"

msg "Staged $(du -sh "$BUILD_DIR/iso" | cut -f1) of files"

# ====================================================================
#  Step 6: Build BIOS El Torito boot image
# ====================================================================
msg "Building BIOS El Torito boot image..."

ELTORITO_DIR="$BUILD_DIR/iso/boot/grub/i386-pc"
mkdir -p "$ELTORITO_DIR"
cat "$CDBOOT_SYS" "$GDISK_SRC/boot/grub/i386-pc/core-patched.img" \
    > "$ELTORITO_DIR/eltorito.img"

msg "BIOS boot image: $(stat -c%s "$ELTORITO_DIR/eltorito.img") bytes"

# ====================================================================
#  Step 7: Build UEFI El Torito boot image (efi.img)
# ====================================================================
msg "Building UEFI boot image (efi.img)..."

EFI_IMG="$BUILD_DIR/iso/boot/grub/efi.img"

dd if=/dev/zero of="$EFI_IMG" bs=1M count=4 status=none
mkfs.vfat -F 12 "$EFI_IMG" >/dev/null

mkdir -p "$EFI_MNT"
mount -o loop "$EFI_IMG" "$EFI_MNT"
mkdir -p "$EFI_MNT/EFI/BOOT"
cp "$GDISK_SRC/EFI/BOOT/BOOTX64.EFI" "$EFI_MNT/EFI/BOOT/BOOTX64.EFI"
sync
umount "$EFI_MNT"
rmdir "$EFI_MNT" 2>/dev/null || true

msg "UEFI boot image: 4MB FAT12 with BOOTX64.EFI"

# ====================================================================
#  Step 8: Build hybrid ISO with xorriso
# ====================================================================
msg "Building hybrid ISO..."
info "  Output: ${HL}$ISO_OUTPUT${NC}"
info "  Label:  ${HL}$ISO_LABEL${NC}"
echo

xorriso -as mkisofs \
    -R -J -joliet-long \
    -iso-level 3 \
    -V "$ISO_LABEL" \
    \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    \
    --grub2-mbr "$HYBRID_MBR" \
    \
    --efi-boot boot/grub/efi.img \
    -efi-boot-part \
    --efi-boot-image \
    \
    --protective-msdos-label \
    \
    -o "$ISO_OUTPUT" \
    "$BUILD_DIR/iso"

# ====================================================================
#  Step 9: Result
# ====================================================================
echo
if [ -f "$ISO_OUTPUT" ]; then
    ISO_SIZE="$(du -h "$ISO_OUTPUT" | cut -f1)"
    rule
    msg "${BOLD}ISO build complete!${NC}"
    rule
    info "File   : ${HL}$(realpath "$ISO_OUTPUT")${NC}"
    info "Size   : ${HL}$ISO_SIZE${NC}"
    info "Label  : ${HL}$ISO_LABEL${NC}"
    info "Source : ${HL}$GDISK_SRC${NC}"
    echo
    info "Boot methods:"
    info "  BIOS : El Torito CD + isohybrid MBR (patched GRUB2)"
    info "  UEFI : El Torito EFI + GPT ESP (patched GRUB2)"
    echo
    info "Write to USB:"
    info "  Linux  : ${DIM}sudo dd if=$ISO_OUTPUT of=/dev/sdX bs=4M status=progress${NC}"
    info "  Windows: ${DIM}Rufus (BIOS+UEFI) / PowerISO / Etcher${NC}"
    echo
else
    die "ISO build failed - output file not found"
fi
