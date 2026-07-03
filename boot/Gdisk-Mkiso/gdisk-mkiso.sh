#!/bin/bash
# ====================================================================
#  gdisk-mkiso.sh  -  Gdisk v3.0 ISO Compiler
# --------------------------------------------------------------------
#  Clones the Gdisk git repository and builds a hybrid bootable ISO
#  that uses the patched GRUB2 for both BIOS and UEFI boot.
#
#  BIOS boot: cdboot.img + core-patched.img (El Torito)
#  UEFI boot: 4MB FAT12 efi.img with EFI/BOOT/BOOTX64.EFI (El Torito)
#  Hybrid:    isohybrid MBR + GPT for direct USB writing
#
#  The resulting ISO can be:
#    - Burned to CD/DVD
#    - Written to USB with Rufus, Etcher, dd, PowerISO
#    - Mounted as virtual CD in QEMU/VirtualBox/VMware
#    - Used as a Gdisk install medium on Windows
#
#  Usage:
#    sudo bash gdisk-mkiso.sh                      # -> ./Gdisk-v3.iso
#    sudo bash gdisk-mkiso.sh /path/to/output.iso  # custom output
#
#  Dependencies: git, xorriso, mkfs.vfat, grub-pc-bin (for cdboot.img)
#
#  Source: https://github.com/GlitchLinux/Gdisk.git
#  License: GPLv3
# ====================================================================

set -euo pipefail

export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"

# -------------------- config --------------------
GDISK_REPO="https://github.com/GlitchLinux/Gdisk.git"
REPO_CACHE="/tmp/gdisk-mkiso-repo"
BUILD_DIR="/tmp/gdisk-mkiso-build-$$"
EFI_MNT="/tmp/gdisk-mkiso-efimnt-$$"
ISO_LABEL="Gdisk-v3"
ISO_OUTPUT="${1:-./Gdisk-v3.iso}"

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
    mountpoint -q "$EFI_MNT" 2>/dev/null && umount "$EFI_MNT" 2>/dev/null
    rm -rf "$BUILD_DIR" "$EFI_MNT" 2>/dev/null
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
                git)        die "missing: git - install with: apt install git" ;;
                *)          die "missing required tool: $t" ;;
            esac
        fi
    done
}
need git xorriso mkfs.vfat rsync

# ====================================================================
#  Step 1: Clone / update Gdisk repository
# ====================================================================
echo
msg "Acquiring Gdisk source files..."

if [ -d "$REPO_CACHE/.git" ]; then
    info "Updating cached repo..."
    git -C "$REPO_CACHE" pull --ff-only 2>/dev/null \
        || { warn "git pull failed, re-cloning..."; rm -rf "$REPO_CACHE"; }
fi

if [ ! -d "$REPO_CACHE/.git" ]; then
    info "Cloning ${HL}$GDISK_REPO${NC}"
    git clone --depth 1 "$GDISK_REPO" "$REPO_CACHE" \
        || die "git clone failed"
fi
msg "Source ready"

# Validate critical files
[ -f "$REPO_CACHE/boot/grub/i386-pc/core-patched.img" ] || die "repo missing core-patched.img"
[ -f "$REPO_CACHE/EFI/BOOT/BOOTX64.EFI" ]               || die "repo missing BOOTX64.EFI"
[ -f "$REPO_CACHE/boot/grub/grub.cfg" ]                  || die "repo missing grub.cfg"

# ====================================================================
#  Step 2: Prepare ISO staging directory
# ====================================================================
msg "Preparing ISO staging area..."
mkdir -p "$BUILD_DIR/iso"

rsync -a --exclude='.git' --exclude='.gitignore' --exclude='.gitattributes' \
      "$REPO_CACHE"/ "$BUILD_DIR/iso"/ \
    || die "rsync failed"

msg "Staged $(du -sh "$BUILD_DIR/iso" | cut -f1) of files"

# ====================================================================
#  Step 3: Build BIOS El Torito boot image
# ====================================================================
msg "Building BIOS El Torito boot image..."

CDBOOT_SYS="/usr/lib/grub/i386-pc/cdboot.img"

if [ ! -f "$CDBOOT_SYS" ]; then
    warn "System cdboot.img not found at $CDBOOT_SYS"
    info "Trying: apt install grub-pc-bin"
    apt-get install -y grub-pc-bin 2>/dev/null || true
    [ -f "$CDBOOT_SYS" ] || die "cdboot.img not found - install grub-pc-bin"
fi

ELTORITO_DIR="$BUILD_DIR/iso/boot/grub/i386-pc"
mkdir -p "$ELTORITO_DIR"
cat "$CDBOOT_SYS" "$REPO_CACHE/boot/grub/i386-pc/core-patched.img" \
    > "$ELTORITO_DIR/eltorito.img"

msg "BIOS boot image: $(stat -c%s "$ELTORITO_DIR/eltorito.img") bytes"

# ====================================================================
#  Step 4: Build UEFI El Torito boot image (efi.img)
# ====================================================================
# Create a 4MB FAT12 partition image with dd + mkfs.vfat,
# loop-mount it, and copy BOOTX64.EFI into it.
msg "Building UEFI boot image (efi.img)..."

EFI_IMG="$BUILD_DIR/iso/boot/grub/efi.img"

dd if=/dev/zero of="$EFI_IMG" bs=1M count=4 status=none
mkfs.vfat -F 12 "$EFI_IMG" >/dev/null

mkdir -p "$EFI_MNT"
mount -o loop "$EFI_IMG" "$EFI_MNT"
mkdir -p "$EFI_MNT/EFI/BOOT"
cp "$REPO_CACHE/EFI/BOOT/BOOTX64.EFI" "$EFI_MNT/EFI/BOOT/BOOTX64.EFI"
sync
umount "$EFI_MNT"
rmdir "$EFI_MNT" 2>/dev/null || true

msg "UEFI boot image: 4MB FAT12 with BOOTX64.EFI"

# ====================================================================
#  Step 5: Build hybrid ISO with xorriso
# ====================================================================
msg "Building hybrid ISO..."
info "  Output: ${HL}$ISO_OUTPUT${NC}"
info "  Label:  ${HL}$ISO_LABEL${NC}"
echo

xorriso -as mkisofs \
    -R -J -joliet-long \
    -V "$ISO_LABEL" \
    \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    \
    -isohybrid-mbr "$CDBOOT_SYS" \
    -isohybrid-gpt-basdat \
    --protective-msdos-label \
    \
    -o "$ISO_OUTPUT" \
    "$BUILD_DIR/iso"

# ====================================================================
#  Step 6: Result
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
    info "Source : ${HL}$GDISK_REPO${NC}"
    echo
    info "Boot methods:"
    info "  BIOS : El Torito + isohybrid MBR (patched GRUB2)"
    info "  UEFI : El Torito EFI + GPT (patched GRUB2)"
    echo
    info "Write to USB:"
    info "  Linux  : ${DIM}sudo dd if=$ISO_OUTPUT of=/dev/sdX bs=4M status=progress${NC}"
    info "  Windows: ${DIM}Rufus / PowerISO / Etcher${NC}"
    echo
else
    die "ISO build failed - output file not found"
fi
