#!/bin/bash
# ====================================================================
#  gdisk-v3-installer.sh  -  Gdisk v3.1 Download ~ Install ~ Repair
# --------------------------------------------------------------------
#  Deploys the Gdisk v3 multiboot GRUB utility to a disk or partition
#  of the user's choice, with selectable disk layout and FAT32 size,
#  while preserving the custom a1ive-patched GRUB core.img boot chain.
#
#  Disk layouts (Create operation):
#    1. Pure FAT32          - single FAT32 partition, whole disk
#    2. FAT32 + NTFS        - 32 MB Gdisk-EFI + sized/full Gdisk-Ntfs
#    3. FAT32 + exFAT       - 32 MB Gdisk-EFI + sized/full Gdisk-exFAT
#
#  For hybrid layouts (2 and 3) the 32 MB FAT32 partition hosts the
#  GRUB modules and BOOTX64.EFI, while the data partition holds the
#  boot images (ISO/IMG/WIM/VHD). VHD native boot requires NTFS.
#
#  Three operations:
#    1. Create  - wipe a whole disk, new MBR table + chosen layout,
#                 clone Gdisk repo, install patched BIOS+UEFI boot.
#    2. Update  - install/refresh Gdisk onto an EXISTING partition
#                 (keeps the partition, refreshes files + boot chain).
#    3. Repair  - reinstall MBR core.img and/or UEFI BOOTX64.EFI on an
#                 existing Gdisk device without touching user data.
#
#  Boot chain is installed from the PREBUILT patched core
#  (core-patched.img) via grub-bios-setup - never regenerated, so the
#  custom modules survive. Mirrors Grub2-Patch.sh patch_bios() logic.
#
#  Source files are pulled from the Gdisk git repository:
#    https://github.com/GlitchLinux/Gdisk.git
#
#  Source: https://github.com/GlitchLinux  (GPLv3)
# ====================================================================

clear

set -uo pipefail

# Ensure system sbin dirs are on PATH (parted, mkfs.vfat, wipefs etc. live there)
export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"

# -------------------- config --------------------
GDISK_REPO="https://github.com/GlitchLinux/Gdisk.git"
FAT_LABEL="Gdisk-v3"
EFI_LABEL="Gdisk-EFI"
NTFS_LABEL="Gdisk-Ntfs"
EXFAT_LABEL="Gdisk-exFAT"
EFI_PART_SIZE="32MiB"      # size of the FAT32 boot partition in hybrid layouts
WORK_DIR="/tmp/gdisk-v3-$$"
DL_DIR="/tmp/gdisk-v3-repo"
MNT="/tmp/gdisk-v3-mnt-$$"
MNT_DATA="/tmp/gdisk-v3-data-$$"

# -------------------- styling --------------------
RED=$'\e[0;31m'; GRN=$'\e[0;32m'; YLW=$'\e[1;33m'
CYN=$'\e[0;36m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; NC=$'\e[0m'
MAGENTA=$'\033[38;5;198m'; BRIGHT_GREEN=$'\033[0;96m'

# semantic shortcuts
HL="$MAGENTA"          # highlight: names, devices, partitions
ACCENT="$CYN"          # section accent
RULE_COLOR="$DIM$CYN"

# thin rule sized to the terminal (falls back to 60 cols)
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

# section header used at the top of every operation/picker screen
header() {
    clear
    echo
    echo "${CYN} ${BOLD}Gdisk v3.0${NC} ❖${NC}${CYN} ${BOLD}$*${NC}"
    echo
}

banner() {
    clear
    echo
    echo "${CYN} ${BOLD}Gdisk v3.0${NC} ❖${NC}${CYN} ${BOLD}Download ~ Install ~ Repair ${NC}"
    echo
}

# -------------------- cleanup --------------------
cleanup() {
    mountpoint -q "$MNT" 2>/dev/null && umount "$MNT" 2>/dev/null
    mountpoint -q "$MNT_DATA" 2>/dev/null && umount "$MNT_DATA" 2>/dev/null
    rm -rf "$WORK_DIR" 2>/dev/null
    rmdir "$MNT" 2>/dev/null
    rmdir "$MNT_DATA" 2>/dev/null
}
trap cleanup EXIT

# -------------------- root --------------------
[ "$(id -u)" -eq 0 ] || die "Run as root:  sudo $0"

# -------------------- tool checks --------------------

# check that any of the given command names exists on PATH
have() {
    local t p
    for t in "$@"; do
        for p in "$t" "/sbin/$t" "/usr/sbin/$t" "/usr/local/sbin/$t"; do
            command -v "$p" >/dev/null 2>&1 && return 0
        done
    done
    return 1
}

# detect package manager (apt / dnf / yum / pacman / zypper) and print the
# install-command prefix on stdout, or empty on stdout with non-zero rc.
detect_pm() {
    if command -v apt-get >/dev/null 2>&1; then echo "apt-get install -y"; return 0; fi
    if command -v dnf     >/dev/null 2>&1; then echo "dnf install -y";     return 0; fi
    if command -v yum     >/dev/null 2>&1; then echo "yum install -y";     return 0; fi
    if command -v pacman  >/dev/null 2>&1; then echo "pacman -S --noconfirm"; return 0; fi
    if command -v zypper  >/dev/null 2>&1; then echo "zypper install -y";  return 0; fi
    return 1
}

# offer to install a set of packages via the detected package manager.
# Returns 0 if installed successfully OR if user declined (caller decides
# whether that is fatal). Returns 1 only on install failure.
offer_install() {
    local label="$1"; shift
    local pkgs=("$@")
    local pm; pm="$(detect_pm)" || {
        warn "no supported package manager detected (apt/dnf/yum/pacman/zypper)"
        warn "please install manually: ${HL}${pkgs[*]}${NC}"
        return 0
    }
    echo
    warn "${label} is not installed."
    info "Suggested install: ${HL}${pm} ${pkgs[*]}${NC}"
    local a
    read -rp "  Install now? [${GRN}Y${NC}/${RED}n${NC}]: " a
    if [[ "$a" =~ ^[Nn]$ ]]; then
        return 0
    fi
    msg "Installing ${label}..."
    # shellcheck disable=SC2086
    $pm "${pkgs[@]}" || { err "install of ${pkgs[*]} failed"; return 1; }
    return 0
}

need() {
    local t
    for t in "$@"; do
        have "$t" || die "missing required tool: $t"
    done
}
need parted git dd lsblk blkid partprobe wipefs sync losetup mkfs.vfat

# Verify grub-pc-bin (BIOS) and grub-efi tooling are available. Without
# these the installer would silently skip BIOS boot setup, leaving a
# UEFI-only device with no warning. Prompt the user to install if missing.
check_boot_tools() {
    local need_install=0

    # BIOS: grub-bios-setup binary (from grub-pc-bin on Debian/Ubuntu,
    # grub2-pc-modules on Fedora, or grub-common elsewhere).
    BIOS_SETUP=""
    for t in grub-bios-setup grub2-bios-setup; do
        for p in "$t" "/sbin/$t" "/usr/sbin/$t"; do
            command -v "$p" >/dev/null 2>&1 && { BIOS_SETUP="$p"; break 2; }
        done
    done

    if [ -z "$BIOS_SETUP" ]; then
        # Package name differs by distro. Try the common ones.
        local pkgs=()
        if command -v apt-get >/dev/null 2>&1; then
            pkgs=(grub-pc-bin grub-common)
        elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
            pkgs=(grub2-pc-modules grub2-tools)
        elif command -v pacman >/dev/null 2>&1; then
            pkgs=(grub)
        elif command -v zypper >/dev/null 2>&1; then
            pkgs=(grub2-i386-pc grub2)
        fi

        offer_install "grub-bios-setup (BIOS boot support)" "${pkgs[@]}" \
            || need_install=1

        # re-detect after install attempt
        for t in grub-bios-setup grub2-bios-setup; do
            for p in "$t" "/sbin/$t" "/usr/sbin/$t"; do
                command -v "$p" >/dev/null 2>&1 && { BIOS_SETUP="$p"; break 2; }
            done
        done

        if [ -z "$BIOS_SETUP" ]; then
            warn "grub-bios-setup still not available."
            warn "Device will boot in ${BOLD}UEFI mode only${NC}${YLW}. BIOS/legacy boot will not work.${NC}"
            echo
            local a
            read -rp "  Continue with UEFI-only install? [${GRN}y${NC}/${RED}N${NC}]: " a
            [[ "$a" =~ ^[Yy]$ ]] || die "aborted - install grub-pc-bin and re-run"
        fi
    fi

    # UEFI: BOOTX64.EFI is shipped in the repo, so no external tool is
    # strictly required, but check for grub-mkimage / grub-install as a
    # sanity signal that a working GRUB2 stack is on the system.
    if ! have grub-install grub2-install grub-mkimage grub2-mkimage; then
        local pkgs=()
        if command -v apt-get >/dev/null 2>&1; then
            pkgs=(grub-efi-amd64-bin grub-common)
        elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
            pkgs=(grub2-efi-x64-modules grub2-tools)
        elif command -v pacman >/dev/null 2>&1; then
            pkgs=(grub efibootmgr)
        elif command -v zypper >/dev/null 2>&1; then
            pkgs=(grub2-x86_64-efi grub2)
        fi
        offer_install "grub-efi (UEFI GRUB stack)" "${pkgs[@]}" || true
    fi

    return 0
}

# Verify the filesystem tools needed for the chosen data partition FS
# are present. Called after the user picks a layout in op_create().
check_datafs_tools() {
    local fs="$1"   # ntfs | exfat | none
    case "$fs" in
        ntfs)
            if ! have mkfs.ntfs mkntfs; then
                local pkgs=()
                if command -v apt-get >/dev/null 2>&1; then pkgs=(ntfs-3g)
                elif command -v dnf >/dev/null 2>&1;   then pkgs=(ntfs-3g ntfsprogs)
                elif command -v yum >/dev/null 2>&1;   then pkgs=(ntfs-3g ntfsprogs)
                elif command -v pacman >/dev/null 2>&1; then pkgs=(ntfs-3g)
                elif command -v zypper >/dev/null 2>&1; then pkgs=(ntfs-3g ntfsprogs)
                fi
                offer_install "mkfs.ntfs (NTFS format tool)" "${pkgs[@]}" \
                    || die "NTFS tools required for FAT32+NTFS layout"
                have mkfs.ntfs mkntfs || die "mkfs.ntfs still not available"
            fi
            ;;
        exfat)
            if ! have mkfs.exfat mkexfatfs; then
                local pkgs=()
                if command -v apt-get >/dev/null 2>&1; then pkgs=(exfatprogs)
                elif command -v dnf >/dev/null 2>&1;   then pkgs=(exfatprogs)
                elif command -v yum >/dev/null 2>&1;   then pkgs=(exfatprogs)
                elif command -v pacman >/dev/null 2>&1; then pkgs=(exfatprogs)
                elif command -v zypper >/dev/null 2>&1; then pkgs=(exfatprogs)
                fi
                offer_install "mkfs.exfat (exFAT format tool)" "${pkgs[@]}" \
                    || die "exFAT tools required for FAT32+exFAT layout"
                have mkfs.exfat mkexfatfs || die "mkfs.exfat still not available"
            fi
            ;;
        none) : ;;
    esac
}

# ====================================================================
#  SOURCE ACQUISITION (git clone)
# ====================================================================
# Clone or update the Gdisk repository.
# Priority:
#   1. Already-cloned copy in $DL_DIR - git pull to update
#   2. Fresh clone from $GDISK_REPO
acquire_sources() {
    if [ -d "$DL_DIR/.git" ]; then
        info "Updating cached Gdisk repo..."
        git -C "$DL_DIR" pull --ff-only 2>/dev/null \
            || { warn "git pull failed, re-cloning..."; rm -rf "$DL_DIR"; }
    fi

    if [ ! -d "$DL_DIR/.git" ]; then
        info "Cloning Gdisk repository..."
        git clone --depth 1 "$GDISK_REPO" "$DL_DIR" \
            || die "git clone failed: $GDISK_REPO"
        msg "Repository cloned"
    else
        msg "Repository up to date"
    fi

    REPO_DIR="$DL_DIR"

    # Validate critical paths exist in the repo
    [ -d "$REPO_DIR/boot/grub/i386-pc" ]    || die "repo missing boot/grub/i386-pc"
    [ -d "$REPO_DIR/boot/grub/x86_64-efi" ] || die "repo missing boot/grub/x86_64-efi"
    [ -f "$REPO_DIR/EFI/BOOT/BOOTX64.EFI" ] || die "repo missing EFI/BOOT/BOOTX64.EFI"

    # Set patch file paths (same structure as repo)
    PATCH_CORE="$REPO_DIR/boot/grub/i386-pc/core-patched.img"
    PATCH_BOOTIMG="$REPO_DIR/boot/grub/i386-pc/boot.img"
    PATCH_I386="$REPO_DIR/boot/grub/i386-pc"
    PATCH_EFIBIN="$REPO_DIR/EFI/BOOT/BOOTX64.EFI"
    PATCH_EFIMODS="$REPO_DIR/boot/grub/x86_64-efi"

    [ -f "$PATCH_CORE" ]    || die "repo missing core-patched.img"
    [ -f "$PATCH_BOOTIMG" ] || die "repo missing boot.img"
}

# ====================================================================
#  DEVICE / PARTITION PICKERS
# ====================================================================
pick_disk() {
    header "Select Target Disk"
    echo "  ${BOLD}Available disks:${NC}" >&2
    echo >&2
    lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -vE '/dev/ram' \
        | sed -E "s#^(/dev/[a-zA-Z0-9]+)#  ${HL}\1${NC}#" >&2
    # also surface backing-file loop devices (e.g. mounted .img for testing)
    local lhdr=0 ln
    while read -r ln; do
        [ -z "$ln" ] && continue
        [ "$lhdr" -eq 0 ] && { echo >&2; echo "  ${DIM}loop devices:${NC}" >&2; lhdr=1; }
        echo "  ${HL}$ln${NC}" >&2
    done < <(losetup -ln -O NAME,SIZE,BACK-FILE 2>/dev/null)
    echo >&2
    local d
    read -rp "  Enter target ${HL}DISK${NC} (e.g. /dev/sdf or /dev/loop5): " d
    [ -b "$d" ] || die "not a block device: $d"
    case "$d" in *[0-9]) [[ "$d" =~ loop[0-9]+$ ]] || warn "That looks like a partition, not a whole disk.";; esac
    REPLY_DISK="$d"
}

pick_partition() {
    header "Select Target Partition"
    echo "  ${BOLD}Available partitions:${NC}" >&2
    echo >&2
    lsblk -pno NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT | grep -vE '/dev/ram' \
        | sed -E "s#(/dev/[a-zA-Z0-9]+)#${HL}\1${NC}#" >&2
    echo >&2
    local p
    read -rp "  Enter target ${HL}PARTITION${NC} (e.g. /dev/sdf1): " p
    [ -b "$p" ] || die "not a block device: $p"
    REPLY_PART="$p"
}

# parent disk + partition number from a partition node
resolve_parent() {
    local part="$1"
    local pk; pk="$(lsblk -no PKNAME "$part" | head -n1)"
    [ -n "$pk" ] || die "cannot resolve parent disk of $part"
    PARENT="/dev/$pk"
    PARTNUM="$(grep -oE '[0-9]+$' <<<"$(basename "$part")")"
    [ -n "$PARTNUM" ] || die "cannot parse partition number from $part"
}

confirm_destroy() {
    local tgt="$1"
    echo
    rule
    warn "ALL DATA on ${HL}${BOLD}$tgt${NC}${YLW} will be DESTROYED.${NC}"
    rule
    echo
    local a
    read -rp "  Type ${BOLD}${GRN}YES${NC} to continue: " a
    [ "$a" = "YES" ] || die "aborted by user"
}

unmount_all() {
    local dev="$1" m
    for m in $(lsblk -lnpo NAME "$dev" 2>/dev/null); do
        while mountpoint -q "$(lsblk -no MOUNTPOINT "$m" | head -n1)" 2>/dev/null; do
            umount "$m" 2>/dev/null || break
        done
        umount "$m" 2>/dev/null || true
    done
}

# ====================================================================
#  CORE STEPS
# ====================================================================

# Helper: derive partition node from disk + index (handles /dev/sdX,
# /dev/nvme0n1, /dev/loopN naming conventions).
part_node() {
    local disk="$1" idx="$2"
    if [[ "$disk" =~ [0-9]$ ]]; then echo "${disk}p${idx}"; else echo "${disk}${idx}"; fi
}

# Wipe disk and write a fresh MBR table + partition layout.
#   layout=fat32          -> one FAT32 partition (size_spec applies)
#   layout=fat32_ntfs     -> 32 MB FAT32 + NTFS partition (size_spec applies to data)
#   layout=fat32_exfat    -> 32 MB FAT32 + exFAT partition (size_spec applies to data)
# Populates globals: BOOT_PART, DATA_PART, DATA_FS
make_layout() {
    local disk="$1" layout="$2" size_spec="$3"
    msg "Wiping ${HL}$disk${NC}"
    wipefs -a "$disk" >/dev/null 2>&1 || true
    dd if=/dev/zero of="$disk" bs=1M count=8 conv=fsync status=none

    parted -s "$disk" mklabel msdos

    case "$layout" in
        fat32)
            msg "Creating single FAT32 partition (${HL}${size_spec}${NC})"
            if [ "$size_spec" = "MAX" ]; then
                parted -s "$disk" mkpart primary fat32 1MiB 100%
            else
                parted -s "$disk" mkpart primary fat32 1MiB "$size_spec"
            fi
            parted -s "$disk" set 1 boot on
            parted -s "$disk" set 1 lba on
            partprobe "$disk"; sleep 1
            BOOT_PART="$(part_node "$disk" 1)"
            DATA_PART=""
            DATA_FS="none"
            ;;

        fat32_ntfs|fat32_exfat)
            local data_fs="ntfs"
            [ "$layout" = "fat32_exfat" ] && data_fs="exfat"
            msg "Creating hybrid layout: FAT32 (${HL}${EFI_PART_SIZE}${NC}) + ${data_fs^^} (${HL}${size_spec}${NC})"

            # FAT32 boot partition: 1MiB .. 1MiB+EFI_PART_SIZE
            # parted accepts a size expression on the end position; use MiB
            # arithmetic so we control alignment precisely.
            local efi_mib="${EFI_PART_SIZE%MiB}"
            local efi_end_mib=$(( 1 + efi_mib ))
            parted -s "$disk" mkpart primary fat32 "1MiB" "${efi_end_mib}MiB"
            parted -s "$disk" set 1 boot on
            parted -s "$disk" set 1 lba on

            if [ "$size_spec" = "MAX" ]; then
                parted -s "$disk" mkpart primary ntfs "${efi_end_mib}MiB" 100%
            else
                # size_spec like "20G" or "4096M" -> compute end as start + spec
                local end_expr
                if [[ "$size_spec" =~ ^([0-9]+)[Gg]$ ]]; then
                    end_expr="$(( efi_end_mib + ${BASH_REMATCH[1]} * 1024 ))MiB"
                elif [[ "$size_spec" =~ ^([0-9]+)[Mm]$ ]]; then
                    end_expr="$(( efi_end_mib + ${BASH_REMATCH[1]} ))MiB"
                else
                    die "invalid size: $size_spec"
                fi
                parted -s "$disk" mkpart primary ntfs "${efi_end_mib}MiB" "$end_expr"
            fi
            partprobe "$disk"; sleep 1

            BOOT_PART="$(part_node "$disk" 1)"
            DATA_PART="$(part_node "$disk" 2)"
            DATA_FS="$data_fs"
            ;;

        *)
            die "unknown layout: $layout"
            ;;
    esac

    [ -b "$BOOT_PART" ] || { partprobe "$disk"; sleep 1; }
    [ -b "$BOOT_PART" ] || die "boot partition node $BOOT_PART did not appear"
    if [ -n "$DATA_PART" ]; then
        [ -b "$DATA_PART" ] || die "data partition node $DATA_PART did not appear"
    fi
}

# Kept for backwards compatibility with older callers (op_update calls
# format_fat directly on the existing partition). Uses FAT_LABEL.
format_fat() {
    local part="$1"
    msg "Formatting ${HL}$part${NC} as FAT32 (label ${HL}$FAT_LABEL${NC})"
    mkfs.vfat -F 32 -n "$FAT_LABEL" "$part" >/dev/null
}

format_boot_fat() {
    local part="$1" label="$2"
    msg "Formatting ${HL}$part${NC} as FAT32 (label ${HL}${label}${NC})"
    mkfs.vfat -F 32 -n "$label" "$part" >/dev/null
}

format_data_ntfs() {
    local part="$1"
    msg "Formatting ${HL}$part${NC} as NTFS (label ${HL}${NTFS_LABEL}${NC})"
    local mk
    if have mkfs.ntfs; then mk="mkfs.ntfs"; else mk="mkntfs"; fi
    "$mk" -Q -F -L "$NTFS_LABEL" "$part" >/dev/null 2>&1 \
        || die "NTFS format failed on $part"
}

format_data_exfat() {
    local part="$1"
    msg "Formatting ${HL}$part${NC} as exFAT (label ${HL}${EXFAT_LABEL}${NC})"
    local mk
    if have mkfs.exfat; then mk="mkfs.exfat"; else mk="mkexfatfs"; fi
    "$mk" -L "$EXFAT_LABEL" "$part" >/dev/null 2>&1 \
        || die "exFAT format failed on $part"
}

deploy_files() {
    local main_part="$1"     # partition that hosts the full /boot/grub tree
    local boot_part="${2:-}" # optional: separate FAT32 partition for EFI (hybrid only)

    mkdir -p "$MNT"
    mount "$main_part" "$MNT" || die "mount $main_part failed"
    msg "Deploying Gdisk files from repo to ${HL}$main_part${NC}"

    # Copy repo contents to main partition, excluding .git metadata
    rsync -a --exclude='.git' --exclude='.gitignore' --exclude='.gitattributes' \
          --exclude='README.md' --exclude='LICENSE' \
          "$REPO_DIR"/ "$MNT"/ \
        || die "file deployment failed"
    sync

    if [ -n "$boot_part" ]; then
        # Hybrid: mount the tiny FAT32 boot partition and put just the
        # UEFI shim + x86_64-efi modules there, so the firmware can pick
        # up BOOTX64.EFI without needing NTFS/exFAT read support.
        mkdir -p "$MNT_DATA"
        mount "$boot_part" "$MNT_DATA" || die "mount $boot_part failed"
        msg "Installing UEFI shim on ${HL}$boot_part${NC}"
        mkdir -p "$MNT_DATA/EFI/BOOT" "$MNT_DATA/boot/grub/x86_64-efi"
        cp -f "$PATCH_EFIBIN" "$MNT_DATA/EFI/BOOT/BOOTX64.EFI"
        cp -f "$PATCH_EFIMODS"/*.mod "$MNT_DATA/boot/grub/x86_64-efi/" 2>/dev/null || true
        cp -f "$PATCH_EFIMODS"/*.lst "$MNT_DATA/boot/grub/x86_64-efi/" 2>/dev/null || true
        # Minimal grub.cfg on the ESP that hands off to the main tree.
        # The full grub.cfg lives on the data partition alongside the
        # rest of Gdisk; the ESP just needs to find it.
        cat > "$MNT_DATA/boot/grub/grub.cfg" <<'ESPEOF'
# Hybrid-layout ESP hand-off: locate the main Gdisk tree and chain to
# its grub.cfg. The main tree lives on Gdisk-Ntfs or Gdisk-exFAT.
insmod part_msdos
insmod ntfs
insmod exfat
insmod search_label
insmod configfile

search --label --no-floppy --set=root Gdisk-Ntfs
if [ -z "${root}" ]; then
    search --label --no-floppy --set=root Gdisk-exFAT
fi

if [ -n "${root}" ]; then
    configfile /boot/grub/grub.cfg
else
    echo "ERROR: Gdisk data partition not found."
    echo "Expected label Gdisk-Ntfs or Gdisk-exFAT."
    sleep 30
fi
ESPEOF
        sync
        umount "$MNT_DATA" 2>/dev/null || true
    fi

    msg "Files deployed"
}

# install patched BIOS core.img into post-MBR gap (reuses patch_bios logic)
# Called with the partition that holds /boot/grub/i386-pc - which is:
#   pure FAT32 layout: the single FAT32 partition
#   hybrid layouts   : the NTFS or exFAT data partition
install_bios_boot() {
    local disk="$1" part="$2"
    [ -n "$BIOS_SETUP" ] || { warn "grub-bios-setup not found (apt install grub-pc-bin) - BIOS boot NOT installed"; return 1; }

    # ensure i386-pc modules + boot images present on the partition
    local moddir="$MNT/boot/grub/i386-pc"
    mkdir -p "$moddir"
    cp -f "$PATCH_I386"/*.mod  "$moddir/" 2>/dev/null || true
    cp -f "$PATCH_I386"/*.lst  "$moddir/" 2>/dev/null || true
    for img in boot.img diskboot.img kernel.img lnxboot.img; do
        [ -f "$PATCH_I386/$img" ] && cp -f "$PATCH_I386/$img" "$moddir/"
    done
    # grub-bios-setup reads boot.img + core.img FROM --directory. Install the
    # PATCHED core under that name so the custom modules are what gets embedded.
    cp -f "$PATCH_CORE" "$moddir/core.img"
    sync

    msg "Installing patched core.img to post-MBR gap via ${HL}$(basename "$BIOS_SETUP")${NC}"
    "$BIOS_SETUP" --directory="$moddir" "$disk" \
        || die "grub-bios-setup failed"
    msg "BIOS boot chain installed"
}

# refresh/ensure UEFI binary + modules (just files on the FAT partition)
install_uefi_boot() {
    msg "Installing UEFI ${HL}BOOTX64.EFI${NC} + x86_64-efi modules"
    mkdir -p "$MNT/EFI/BOOT" "$MNT/boot/grub/x86_64-efi"
    [ -f "$PATCH_EFIBIN" ] && cp -f "$PATCH_EFIBIN" "$MNT/EFI/BOOT/BOOTX64.EFI"
    cp -f "$PATCH_EFIMODS"/*.mod "$MNT/boot/grub/x86_64-efi/" 2>/dev/null || true
    cp -f "$PATCH_EFIMODS"/*.lst "$MNT/boot/grub/x86_64-efi/" 2>/dev/null || true
    sync
}

# ====================================================================
#  OPERATIONS
# ====================================================================

op_create() {
    header "Create Gdisk Device"
    info "CREATE - new Gdisk device on a whole disk"
    check_boot_tools
    acquire_sources
    pick_disk
    local disk="$REPLY_DISK"
    confirm_destroy "$disk"

    # layout selection
    header "Select Gdisk Filesystem Setup"
    echo "  ${BOLD}1.${NC} ${HL}Pure FAT32${NC}       ~ single FAT32 partition (simplest, 4 GiB file cap)"
    echo "  ${BOLD}2.${NC} ${HL}FAT32 + NTFS${NC}     ~ 32 MB Gdisk-EFI + Gdisk-Ntfs   (${GRN}recommended${NC}, supports VHD native boot)"
    echo "  ${BOLD}3.${NC} ${HL}FAT32 + exFAT${NC}    ~ 32 MB Gdisk-EFI + Gdisk-exFAT  (cross-platform, no VHD native boot)"
    echo
    local L LAYOUT
    read -rp "  > " L
    case "$L" in
        1) LAYOUT="fat32" ;;
        2) LAYOUT="fat32_ntfs"  ; check_datafs_tools ntfs ;;
        3) LAYOUT="fat32_exfat" ; check_datafs_tools exfat ;;
        *) die "invalid choice: $L" ;;
    esac

    # size selection: applies to the (single|data) partition
    header "Partition Size"
    if [ "$LAYOUT" = "fat32" ]; then
        echo "  ${BOLD}FAT32${NC} partition size:"
    else
        echo "  ${BOLD}Data${NC} partition size (the 32 MB ${HL}Gdisk-EFI${NC} partition is fixed):"
    fi
    echo "    ${BOLD}1.${NC} ${HL}Fill entire disk${NC} ~ recommended"
    echo "    ${BOLD}2.${NC} ${HL}Custom size${NC}      ~ e.g. 8G, 16G, 4096M"
    echo
    local s sz
    read -rp "  > " s
    if [ "$s" = "2" ]; then
        echo
        read -rp "  Enter size (e.g. ${HL}8G${NC}): " sz
        [[ "$sz" =~ ^[0-9]+[MGmg]$ ]] || die "invalid size: $sz"
        SIZESPEC="$sz"
    else
        SIZESPEC="MAX"
    fi

    header "Building Gdisk Device"
    unmount_all "$disk"
    make_layout "$disk" "$LAYOUT" "$SIZESPEC"

    case "$LAYOUT" in
        fat32)
            format_boot_fat "$BOOT_PART" "$FAT_LABEL"
            deploy_files "$BOOT_PART"
            install_uefi_boot
            install_bios_boot "$disk" "$BOOT_PART"
            finalize "$disk" "$BOOT_PART"
            ;;
        fat32_ntfs)
            format_boot_fat "$BOOT_PART" "$EFI_LABEL"
            format_data_ntfs "$DATA_PART"
            # Main tree goes on NTFS; ESP gets a UEFI shim + hand-off
            deploy_files "$DATA_PART" "$BOOT_PART"
            # BIOS boot: /boot/grub lives on NTFS, so aim grub-bios-setup there
            install_bios_boot "$disk" "$DATA_PART"
            finalize "$disk" "$DATA_PART"
            ;;
        fat32_exfat)
            format_boot_fat "$BOOT_PART" "$EFI_LABEL"
            format_data_exfat "$DATA_PART"
            deploy_files "$DATA_PART" "$BOOT_PART"
            install_bios_boot "$disk" "$DATA_PART"
            finalize "$disk" "$DATA_PART"
            ;;
    esac
}

op_update() {
    header "Update Gdisk"
    info "UPDATE - install/refresh Gdisk onto an EXISTING partition"
    check_boot_tools
    acquire_sources
    pick_partition
    local part="$REPLY_PART"
    resolve_parent "$part"

    local fstype; fstype="$(blkid -o value -s TYPE "$part" 2>/dev/null)"
    case "$fstype" in
        vfat|fat|fat32|msdos)
            info "Target filesystem: ${HL}FAT32${NC}"
            ;;
        ntfs)
            info "Target filesystem: ${HL}NTFS${NC} (hybrid-layout data partition, supported)"
            ;;
        exfat)
            info "Target filesystem: ${HL}exFAT${NC} (hybrid-layout data partition, supported)"
            ;;
        "")
            warn "no filesystem detected on ${HL}$part${NC}"
            warn "will format as FAT32"
            ;;
        *)
            warn "filesystem is '${HL}$fstype${NC}${YLW}' - Gdisk expects FAT32, NTFS or exFAT"
            ;;
    esac

    echo
    warn "Existing files on ${HL}${BOLD}$part${NC}${YLW} are kept; Gdisk files will be added/overwritten.${NC}"
    echo
    read -rp "  Proceed? [${GRN}y${NC}/${RED}N${NC}]: " a
    [[ "$a" =~ ^[Yy]$ ]] || die "aborted"

    header "Updating Gdisk"
    unmount_all "$PARENT"
    [ "$fstype" = "" ] && format_fat "$part"
    deploy_files "$part"
    install_uefi_boot
    install_bios_boot "$PARENT" "$part"
    finalize "$PARENT" "$part"
}

op_repair() {
    header "Repair Gdisk"
    info "REPAIR - fix MBR / UEFI boot on an existing Gdisk device"
    check_boot_tools
    acquire_sources
    pick_partition
    local part="$REPLY_PART"
    resolve_parent "$part"

    header "Repair Target"
    echo "  ${BOLD}1.${NC} ${HL}BIOS${NC} ~ MBR + core.img"
    echo "  ${BOLD}2.${NC} ${HL}UEFI${NC} ~ BOOTX64.EFI + modules"
    echo "  ${BOLD}3.${NC} ${HL}Both${NC} ~ BIOS + UEFI"
    echo
    local r; read -rp "  > " r

    header "Repairing Gdisk"
    unmount_all "$PARENT"
    mkdir -p "$MNT"; mount "$part" "$MNT" || die "mount $part failed"

    case "$r" in
        1) install_bios_boot "$PARENT" "$part" ;;
        2) install_uefi_boot ;;
        3) install_uefi_boot; install_bios_boot "$PARENT" "$part" ;;
        *) die "invalid choice" ;;
    esac
    finalize "$PARENT" "$part"
}

finalize() {
    local disk="$1" part="$2"
    sync
    mountpoint -q "$MNT" && umount "$MNT" 2>/dev/null
    partprobe "$disk" 2>/dev/null || true
    echo
    rule
    msg "${BOLD}Done.${NC}"
    rule
    info "Device : ${HL}$disk${NC}"
    info "Part   : ${HL}$part${NC}  ($(lsblk -no SIZE "$part" 2>/dev/null | tr -d ' '))"
    local plabel; plabel="$(lsblk -no LABEL "$part" 2>/dev/null | tr -d ' ')"
    [ -n "$plabel" ] && info "Label  : ${HL}$plabel${NC}"
    local pfs; pfs="$(blkid -o value -s TYPE "$part" 2>/dev/null)"
    [ -n "$pfs" ] && info "FS     : ${HL}$pfs${NC}"
    info "Source : ${HL}$GDISK_REPO${NC}"
    echo
    echo "  ${BRIGHT_GREEN}${BOLD}Gdisk v3.1 is ready.${NC} ${GRN}Boot the target in BIOS or UEFI mode.${NC}"
    echo
}

# ====================================================================
#  MENU
# ====================================================================
banner
echo "  ${BOLD}Select Gdisk Operation [1-3]:${NC}"
echo
echo "  ${BOLD}1.${NC} ${MAGENTA}Create Gdisk${NC} ~ Make a new Gdisk Device"
echo "  ${BOLD}2.${NC} ${MAGENTA}Update Gdisk${NC} ~ Update or Install on existing partition."
echo "  ${BOLD}3.${NC} ${MAGENTA}Repair Gdisk${NC} ~ Fix MBR & UEFI Boot on existing Gdisk device."
echo
read -rp "  > " CHOICE
echo

case "$CHOICE" in
    1) op_create ;;
    2) op_update ;;
    3) op_repair ;;
    *) die "invalid choice: $CHOICE" ;;
esac
