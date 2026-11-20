#!/bin/bash
cat > /tmp/.gdisk-grub-patch << 'PATCH'
#!/bin/bash
# gdisk-grub-patch.sh - Add/remove Gdisk from the host system's GRUB boot menu
#
# Usage:
#   sudo ./gdisk-grub-patch.sh install   - Clone Gdisk, set up EFI chainloader, add GRUB entry
#   sudo ./gdisk-grub-patch.sh update    - Pull latest Gdisk and refresh everything
#   sudo ./gdisk-grub-patch.sh remove    - Remove Gdisk from GRUB, clean up EFI, delete /boot/gdisk
#
# UEFI: Copies Gdisk's BOOTX64.EFI to the EFI partition and chainloads it.
#       Gdisk's EFI auto-finds /boot/grub/gdisk.cfg (a redirect stub) which
#       loads the full Gdisk config from /boot/gdisk/boot/grub/gdisk.cfg.
#       This gives Gdisk its own a1ive GRUB core with map, ntboot, vhd, etc.
#
# BIOS: Directly loads Gdisk's config via configfile (host GRUB modules suffice
#       for basic operation; a1ive-specific features like map won't work in BIOS).
#
# Requirements: git, python3, grub (update-grub or grub2-mkconfig)
# License: GPLv3

set -e

GDISK_DIR="/boot/gdisk"
GRUB_D_DIR=""
UPDATE_GRUB=""
EFI_PART=""
EFI_UUID=""
IS_EFI=0

# ── Detect grub.d location and update command ──
detect_grub() {
    if [ -d /etc/grub.d ]; then
        GRUB_D_DIR="/etc/grub.d"
    else
        echo "Error: /etc/grub.d not found. Is GRUB installed?"
        exit 1
    fi

    if command -v update-grub >/dev/null 2>&1; then
        UPDATE_GRUB="update-grub"
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        UPDATE_GRUB="grub2-mkconfig -o /boot/grub2/grub.cfg"
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        UPDATE_GRUB="grub-mkconfig -o /boot/grub/grub.cfg"
    else
        echo "Error: No grub config generator found."
        exit 1
    fi
}

# ── Detect EFI partition (regardless of current boot mode) ──
detect_efi() {
    # Find EFI mount point
    EFI_PART=$(findmnt -no TARGET /boot/efi 2>/dev/null || findmnt -no TARGET /efi 2>/dev/null || echo "")

    if [ -z "$EFI_PART" ] || [ ! -d "$EFI_PART/EFI" ]; then
        echo "  No EFI partition found/mounted - UEFI chainloader will not be set up."
        echo "  BIOS boot entry will still work."
        IS_EFI=0
        return
    fi

    # Get UUID of EFI partition
    local efi_dev
    efi_dev=$(findmnt -no SOURCE "$EFI_PART" 2>/dev/null)
    EFI_UUID=$(blkid -s UUID -o value "$efi_dev" 2>/dev/null)

    if [ -z "$EFI_UUID" ]; then
        echo "  Warning: Could not determine EFI partition UUID."
        IS_EFI=0
        return
    fi

    IS_EFI=1
    echo "  EFI partition: $EFI_PART (UUID: $EFI_UUID)"
}

# ── Check root ──
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root."
        exit 1
    fi
}

# ── Rewrite Gdisk internal paths for nested /boot/gdisk/ install ──
rewrite_paths() {
    local prefix="$1"

    if [ ! -d "$prefix/boot/grub" ]; then
        echo "Error: $prefix/boot/grub not found"
        exit 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: python3 is required for path rewriting."
        exit 1
    fi

    echo "Rewriting internal paths: /boot/grub/ -> $prefix/boot/grub/"

    local count=0

    for cfg in $(find "$prefix/boot/grub" -name "*.cfg" -type f); do
        [ -f "$cfg" ] || continue

        if ! grep -q '/boot/grub/' "$cfg"; then
            continue
        fi

        python3 << PYEOF
with open("$cfg") as f:
    lines = f.readlines()

prefix = "$prefix"
out = []
in_loop = False

for line in lines:
    stripped = line.strip()

    if ('set root=loop' in stripped or 'root=(loop)' in stripped or
        '(loop)/boot/grub' in stripped):
        in_loop = True

    if in_loop and ('return 0' in stripped or 'loopback --delete' in stripped):
        out.append(line)
        in_loop = False
        continue

    if stripped.startswith('menuentry ') or stripped.startswith('function '):
        in_loop = False

    if in_loop:
        out.append(line)
        continue

    line = line.replace('(loop)/boot/grub/', '(loop)/__PBG__/')
    line = line.replace('(loop)/boot/grub2/', '(loop)/__PBG2__/')

    line = line.replace('/boot/grub/', prefix + '/boot/grub/')

    line = line.replace('(loop)/__PBG__/', '(loop)/boot/grub/')
    line = line.replace('(loop)/__PBG2__/', '(loop)/boot/grub2/')

    out.append(line)

with open("$cfg", "w") as f:
    f.writelines(out)
PYEOF

        count=$((count + 1))
    done

    echo "Rewrote paths in $count .cfg files."
}

# ── Set up EFI chainloader ──
setup_efi() {
    local gdisk_efi="$GDISK_DIR/EFI/BOOT/BOOTX64.EFI"

    if [ ! -f "$gdisk_efi" ]; then
        echo "  Warning: Gdisk BOOTX64.EFI not found - skipping EFI setup."
        IS_EFI=0
        return
    fi

    # Create Gdisk EFI directory on EFI partition
    mkdir -p "$EFI_PART/EFI/gdisk"
    cp "$gdisk_efi" "$EFI_PART/EFI/gdisk/BOOTX64.EFI"
    echo "  Copied BOOTX64.EFI to $EFI_PART/EFI/gdisk/"

    # Create redirect stub at /boot/grub/gdisk.cfg
    # Gdisk's BOOTX64.EFI auto-searches for /boot/grub/gdisk.cfg and loads it.
    # This stub redirects to the full config in the nested Gdisk install.
    cat > /boot/grub/gdisk.cfg << 'STUBEOF'
configfile /boot/gdisk/boot/grub/gdisk.cfg
STUBEOF
    echo "  Created redirect stub at /boot/grub/gdisk.cfg"
}

# ── Clean up EFI ──
cleanup_efi() {
    # Remove Gdisk from EFI partition
    if [ -n "$EFI_PART" ] && [ -d "$EFI_PART/EFI/gdisk" ]; then
        rm -rf "$EFI_PART/EFI/gdisk"
        echo "  Removed $EFI_PART/EFI/gdisk/"
    fi

    # Remove redirect stub
    if [ -f /boot/grub/gdisk.cfg ]; then
        rm -f /boot/grub/gdisk.cfg
        echo "  Removed /boot/grub/gdisk.cfg"
    fi
}

# ── Install GRUB hook ──
install_hook() {
    echo "Installing GRUB hook at $GRUB_D_DIR/99-gdisk..."

    # Both EFI and BIOS entries are written; GRUB picks the right one
    # at boot time via ${grub_platform}.
    # EFI UUID is needed for the chainloader path.
    cat > "$GRUB_D_DIR/99-gdisk" << GRUBEOF
#!/bin/sh
exec tail -n +3 "\$0"

if [ "\${grub_platform}" = "efi" ]; then
    menuentry "Gdisk v3.2" --class gdisk --class boot {
        insmod chain
        insmod fat
        insmod search_fs_uuid
        search --no-floppy --fs-uuid --set=root $EFI_UUID
        chainloader /EFI/gdisk/BOOTX64.EFI
    }
fi

if [ "\${grub_platform}" = "pc" ]; then
    menuentry "Gdisk v3.2" --class gdisk --class boot {
        configfile /boot/gdisk/boot/grub/gdisk.cfg
    }
fi
GRUBEOF

    chmod +x "$GRUB_D_DIR/99-gdisk"
}

# ── Install ──
do_install() {
    if [ -d "$GDISK_DIR/boot/grub" ]; then
        echo "Gdisk is already installed at $GDISK_DIR"
        echo "Use 'update' to pull the latest version, or 'remove' first."
        exit 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo "Error: git is required."
        exit 1
    fi

    echo "=== Cloning Gdisk ==="
    git clone --depth 1 https://github.com/GlitchLinux/Gdisk.git "$GDISK_DIR"

    echo ""
    echo "=== Rewriting paths ==="
    rewrite_paths "$GDISK_DIR"

    echo ""
    echo "=== Setting up EFI ==="
    detect_efi

    if [ "$IS_EFI" -eq 1 ]; then
        setup_efi
    fi

    echo ""
    echo "=== Installing GRUB hook ==="
    install_hook

    echo ""
    echo "Updating GRUB configuration..."
    $UPDATE_GRUB

    echo ""
    echo "========================================="
    echo " Gdisk installed successfully!"
    if [ "$IS_EFI" -eq 1 ]; then
        echo " UEFI: chainloader via EFI partition"
    else
        echo " Note: No EFI partition found."
        echo " UEFI chainloader not installed."
    fi
    echo " BIOS: configfile (always available)"
    echo ""
    echo " Reboot and select 'Gdisk v3.2'"
    echo " from the GRUB boot menu."
    echo "========================================="
}

# ── Update ──
do_update() {
    if [ ! -d "$GDISK_DIR/.git" ]; then
        echo "Error: Gdisk is not installed at $GDISK_DIR."
        echo "Run 'install' first."
        exit 1
    fi

    echo "=== Pulling latest Gdisk ==="
    cd "$GDISK_DIR" && git checkout -- . && git pull

    echo ""
    echo "=== Rewriting paths ==="
    rewrite_paths "$GDISK_DIR"

    echo ""
    echo "=== Setting up EFI ==="
    detect_efi

    if [ "$IS_EFI" -eq 1 ]; then
        setup_efi
    fi

    # Ensure hook is still in place
    if [ ! -x "$GRUB_D_DIR/99-gdisk" ]; then
        echo ""
        install_hook
    fi

    echo ""
    echo "Updating GRUB configuration..."
    $UPDATE_GRUB

    echo ""
    echo "Done. Gdisk has been updated."
}

# ── Remove ──
do_remove() {
    echo "=== Removing Gdisk ==="

    if [ -f "$GRUB_D_DIR/99-gdisk" ]; then
        rm -f "$GRUB_D_DIR/99-gdisk"
        echo "Removed GRUB hook."
    fi

    echo ""
    echo "=== Cleaning up EFI ==="
    detect_efi
    cleanup_efi

    if [ -d "$GDISK_DIR" ]; then
        rm -rf "$GDISK_DIR"
        echo "Removed $GDISK_DIR"
    fi

    echo ""
    echo "Updating GRUB configuration..."
    $UPDATE_GRUB

    echo ""
    echo "Done. Gdisk has been removed."
}

# ── Main ──
check_root
detect_grub

case "${1:-}" in
    install)
        do_install
        ;;
    update)
        do_update
        ;;
    remove)
        do_remove
        ;;
    *)
        echo "Gdisk GRUB Patcher"
        echo ""
        echo "Usage: sudo $0 {install|update|remove}"
        echo ""
        echo "  install  - Clone Gdisk, set up EFI/BIOS boot, add GRUB entry"
        echo "  update   - Pull latest Gdisk, refresh EFI and paths"
        echo "  remove   - Remove Gdisk, clean up EFI, restore GRUB"
        exit 0
        ;;
esac

PATCH

sudo chmod +x /tmp/.gdisk-grub-patch

clear
echo
echo " 1. Gdisk Grub Install"
echo " 2. Gdisk Grub Update"
echo " 3. Gdisk Grub Remove"
echo 
read -p " > Select [1-3]: " choice

case $choice in
    1)
        clear
	sudo bash /tmp/.gdisk-grub-patch install 
        ;;
    2)
	clear
	sudo bash /tmp/.gdisk-grub-patch update	
        ;;
    3)
	clear
	sudo bash /tmp/.gdisk-grub-patch remove
        ;;
    *)
        echo "Invalid Choice, Exiting"
        sudo rm -f /tmp/.gdisk-grub-patch
        ;;
esac
