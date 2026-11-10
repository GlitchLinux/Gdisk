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
#    4. Setup  -  Prepares a Linux system inside a .gdisk virtual disk."
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

set -uo pipefail

# Only clear the terminal in interactive mode. GUI mode captures stdout
# as log lines - a clear would just print escape garbage.
[ -t 1 ] && clear

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

# -------------------- GUI-mode args --------------------
# Non-interactive mode driven by the GUI wrapper. All operation inputs
# come in as flags; interactive prompts are suppressed; stdout emits
# machine-readable prefixes (STEP:, MSG:, WARN:, ERR:, PROGRESS:n/m,
# DONE:, FAIL:, PICK:...) that the GUI parses line-by-line.
GUI_MODE=0
GUI_OP=""              # create | update | repair
GUI_DISK=""            # /dev/sdX for create
GUI_PART=""            # /dev/sdX1 for update/repair
GUI_LAYOUT=""          # fat32 | fat32_ntfs | fat32_exfat
GUI_SIZESPEC=""        # MAX or NN[MG]
GUI_REPAIR_TARGET=""   # bios | uefi | both
GUI_AUTO_INSTALL_DEPS=0  # 1 = auto-answer Y to install prompts

while [ $# -gt 0 ]; do
    case "$1" in
        --gui)                GUI_MODE=1 ;;
        --op=*)               GUI_OP="${1#*=}" ;;
        --disk=*)             GUI_DISK="${1#*=}" ;;
        --part=*)             GUI_PART="${1#*=}" ;;
        --layout=*)           GUI_LAYOUT="${1#*=}" ;;
        --size=*)             GUI_SIZESPEC="${1#*=}" ;;
        --repair-target=*)    GUI_REPAIR_TARGET="${1#*=}" ;;
        --auto-install-deps)  GUI_AUTO_INSTALL_DEPS=1 ;;
        --help|-h)
            cat <<HELP
Usage (interactive): $0
Usage (GUI mode):    $0 --gui --op=OP [options]

Operations:
    --op=create  --disk=/dev/sdX --layout={fat32|fat32_ntfs|fat32_exfat}
                 --size={MAX|NNG|NNM}
    --op=update  --part=/dev/sdX1
    --op=repair  --part=/dev/sdX1 --repair-target={bios|uefi|both}

Common:
    --gui                   Non-interactive, machine-parseable output
    --auto-install-deps     Auto-answer Y to install-missing-tool prompts

Without --gui the installer runs its normal interactive menu.
HELP
            exit 0
            ;;
        *)  # unknown: let the rest of the script try to handle
            break
            ;;
    esac
    shift
done

# -------------------- styling --------------------
RED=$'\e[0;31m'; GRN=$'\e[0;32m'; YLW=$'\e[1;33m'
CYN=$'\e[0;36m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; NC=$'\e[0m'
MAGENTA=$'\033[38;5;198m'; BRIGHT_GREEN=$'\033[0;96m'

# In GUI mode, suppress ANSI colour sequences so the log pane shows
# clean text. The GUI will colour by prefix instead.
if [ "$GUI_MODE" = "1" ]; then
    RED=""; GRN=""; YLW=""; CYN=""; BOLD=""; DIM=""; NC=""
    MAGENTA=""; BRIGHT_GREEN=""
fi

# semantic shortcuts
HL="$MAGENTA"          # highlight: names, devices, partitions
ACCENT="$CYN"          # section accent
RULE_COLOR="$DIM$CYN"

# thin rule sized to the terminal (falls back to 60 cols)
rule() {
    [ "$GUI_MODE" = "1" ] && return 0
    local w; w="$(tput cols 2>/dev/null || echo 60)"
    [ "$w" -gt 70 ] && w=70
    printf "${RULE_COLOR}%*s${NC}\n" "$w" '' | tr ' ' '-'
}

# In GUI mode every status line gets a machine-readable prefix so the
# wrapper can tag it (colour, severity, step counter). In CLI mode we
# emit the pretty coloured text unchanged.
if [ "$GUI_MODE" = "1" ]; then
    msg()  { echo "MSG: $*"; }
    warn() { echo "WARN: $*"; }
    err()  { echo "ERR: $*" >&2; }
    info() { echo "INFO: $*"; }
    die()  { echo "FAIL: $*" >&2; cleanup; exit 1; }
    header() { echo "STEP: $*"; }
    banner() { echo "STEP: Gdisk v3.2 - Download ~ Install ~ Repair"; }
else
    msg()  { echo -e "${GRN}[+]${NC} $*"; }
    warn() { echo -e "${YLW}[!]${NC} $*"; }
    err()  { echo -e "${RED}[x]${NC} $*"; }
    info() { echo -e "${CYN}[i]${NC} $*"; }
    die()  { err "$*"; cleanup; exit 1; }
    header() {
        clear
        echo
        echo "${CYN} ${BOLD}Gdisk v3.2${NC} ❖${NC}${CYN} ${BOLD}$*${NC}"
        echo
    }
    banner() {
        clear
        echo
        echo "${CYN} ${BOLD}Gdisk v3.2${NC} ❖${NC}${CYN} ${BOLD}Download ~ Install ~ Repair ${NC}"
        echo
    }
fi

# -------------------- cleanup --------------------
cleanup() {
    mountpoint -q "$MNT" 2>/dev/null && umount "$MNT" 2>/dev/null
    mountpoint -q "$MNT_DATA" 2>/dev/null && umount "$MNT_DATA" 2>/dev/null
    rm -rf "$WORK_DIR" 2>/dev/null
    [ -n "${EFI_IMG_STAGE:-}" ] && rm -rf "$EFI_IMG_STAGE" 2>/dev/null
    rm -rf /tmp/gdisk-grub-offline-$$ 2>/dev/null
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

# refresh the package index for the detected pm. Runs once per invocation.
PM_INDEX_REFRESHED=0
pm_refresh() {
    [ "$PM_INDEX_REFRESHED" = "1" ] && return 0
    msg "Refreshing package index..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1 || warn "apt-get update failed (continuing)"
    elif command -v dnf >/dev/null 2>&1; then
        dnf -q makecache >/dev/null 2>&1 || warn "dnf makecache failed (continuing)"
    elif command -v yum >/dev/null 2>&1; then
        yum -q makecache >/dev/null 2>&1 || warn "yum makecache failed (continuing)"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm >/dev/null 2>&1 || warn "pacman -Sy failed (continuing)"
    elif command -v zypper >/dev/null 2>&1; then
        zypper -q refresh >/dev/null 2>&1 || warn "zypper refresh failed (continuing)"
    fi
    PM_INDEX_REFRESHED=1
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
    if [ "$GUI_MODE" = "1" ]; then
        if [ "$GUI_AUTO_INSTALL_DEPS" = "1" ]; then
            a="Y"
            info "GUI mode: auto-installing"
        else
            warn "GUI mode: --auto-install-deps not set, skipping install"
            return 0
        fi
    else
        read -rp "  Install now? [${GRN}Y${NC}/${RED}n${NC}]: " a
    fi
    if [[ "$a" =~ ^[Nn]$ ]]; then
        return 0
    fi
    pm_refresh
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
need parted git dd lsblk blkid partprobe wipefs sync losetup mkfs.vfat tar rsync ar

# xz is required to extract the pre-built EFI image (Gdisk-Efi.tar.xz)
# and the bundled grub-pc .deb (grub-pc-efi.tar.xz). Prompt to install
# it up-front so the user doesn't hit an opaque tar failure mid-install.
check_xz() {
    have xz && return 0
    local pkgs=()
    if command -v apt-get >/dev/null 2>&1; then
        pkgs=(xz-utils)
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        pkgs=(xz)
    elif command -v pacman >/dev/null 2>&1; then
        pkgs=(xz)
    elif command -v zypper >/dev/null 2>&1; then
        pkgs=(xz)
    fi
    offer_install "xz (needed to extract Gdisk-Efi.tar.xz and bundled .deb)" \
        "${pkgs[@]}" || die "xz is required to proceed"
    have xz || die "xz still not available after install"
}

# Absolute paths to installer-shipped helpers. Populated by
# install-time detection - the installer runs from various working
# directories (repo checkout, USB root, systemd service) so we resolve
# them once relative to the script location.
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer the cached git clone if it holds the offline bundle files,
# since the installer itself may have been fetched to /tmp via wget
# where the .tar.xz.sh helpers are not present.
resolve_installer_dir() {
    local clone_dir="$DL_DIR/boot/Gdisk-Installer"
    if [ ! -f "$INSTALLER_DIR/Gdisk-Efi.tar.xz.sh" ] && \
       [ -f "$clone_dir/Gdisk-Efi.tar.xz.sh" ]; then
        INSTALLER_DIR="$clone_dir"
    fi
}

# Attempt to extract /usr/sbin/grub-bios-setup from the bundled offline
# .deb (grub-pc_2.12-9+deb13u2_amd64.deb). Populates BIOS_SETUP on
# success. This is the "offline fallback" path for systems where apt
# install failed to place grub-bios-setup on PATH (missing repos,
# broken mirror, etc.).
extract_bundled_grub() {
    local rebuild_sh="$INSTALLER_DIR/grub-pc-efi.tar.xz.sh"
    local bundle="$INSTALLER_DIR/grub-pc-efi.tar.xz"
    local stagedir="/tmp/gdisk-grub-offline-$$"

    if [ ! -f "$bundle" ] && [ ! -f "$rebuild_sh" ]; then
        warn "no bundled grub-pc-efi.tar.xz(.sh) found beside installer"
        return 1
    fi

    mkdir -p "$stagedir"

    # Rebuild the tarball from the self-extracting script if the raw
    # tar.xz is not present.
    if [ ! -f "$bundle" ]; then
        info "Rebuilding bundled grub .deb archive..."
        ( cd "$stagedir" && cp "$rebuild_sh" . && \
          bash "$(basename "$rebuild_sh")" </dev/null >/dev/null 2>&1 ) \
            || { warn "bundled archive rebuild failed"; rm -rf "$stagedir"; return 1; }
        bundle="$stagedir/grub-pc-efi.tar.xz"
        [ -f "$bundle" ] || { warn "expected $bundle after rebuild"; rm -rf "$stagedir"; return 1; }
    fi

    info "Extracting grub-bios-setup from bundled .deb..."
    tar -xJf "$bundle" -C "$stagedir" || { warn "tar extract failed"; rm -rf "$stagedir"; return 1; }

    local deb; deb="$(ls "$stagedir"/grub-pc_*.deb 2>/dev/null | head -1)"
    [ -f "$deb" ] || { warn "grub-pc .deb not found in bundle"; rm -rf "$stagedir"; return 1; }

    # Extract the .deb's data.tar.xz. Debian's grub-pc .deb only
    # contains SYMLINKS to the actual binaries (which live in
    # grub-pc-bin's /usr/lib/grub/i386-pc/ tree). Try the real path
    # first, and if it isn't in this payload, fall back to resolving
    # the /usr/sbin/ symlink and extracting whichever real file it
    # points at.
    ( cd "$stagedir" && ar x "$deb" data.tar.xz ) \
        || { warn "ar extract of data.tar.xz failed"; rm -rf "$stagedir"; return 1; }

    local extracted=""
    if tar -xJf "$stagedir/data.tar.xz" -C "$stagedir" \
            ./usr/lib/grub/i386-pc/grub-bios-setup 2>/dev/null; then
        extracted="$stagedir/usr/lib/grub/i386-pc/grub-bios-setup"
    elif tar -xJf "$stagedir/data.tar.xz" -C "$stagedir" \
            ./usr/sbin/grub-bios-setup 2>/dev/null; then
        # Might be a symlink; if so, follow it and extract the target
        # from the same tarball.
        local link="$stagedir/usr/sbin/grub-bios-setup"
        if [ -L "$link" ]; then
            local tgt; tgt="$(readlink "$link")"
            # tgt is usually "../lib/grub/i386-pc/grub-bios-setup"
            local abs="./usr/${tgt#../}"
            if tar -xJf "$stagedir/data.tar.xz" -C "$stagedir" "$abs" 2>/dev/null; then
                extracted="$stagedir/${abs#./}"
            fi
        elif [ -f "$link" ]; then
            extracted="$link"
        fi
    fi

    if [ -z "$extracted" ] || [ ! -f "$extracted" ]; then
        warn "grub-bios-setup binary not present in bundled .deb"
        warn "(bundle only contains symlinks; the actual binary lives in grub-pc-bin)"
        rm -rf "$stagedir"
        return 1
    fi

    mkdir -p /usr/local/sbin
    install -m 755 "$extracted" /usr/local/sbin/grub-bios-setup \
        || { warn "install of grub-bios-setup failed"; rm -rf "$stagedir"; return 1; }

    rm -rf "$stagedir"
    BIOS_SETUP="/usr/local/sbin/grub-bios-setup"
    msg "Bundled grub-bios-setup installed at ${HL}${BIOS_SETUP}${NC}"
    return 0
}

# Locate grub-bios-setup, checking both standard PATH and the Debian
# location. On Debian 12/13 the binary lives at
# /usr/lib/grub/i386-pc/grub-bios-setup and is NOT on PATH - the
# /usr/sbin/grub-bios-setup symlink is provided by the grub-pc
# metapackage, not by grub-pc-bin, so a system with just grub-pc-bin
# installed will only have the /usr/lib/grub/... path. Populates
# BIOS_SETUP on success.
locate_bios_setup() {
    BIOS_SETUP=""
    local t p
    for t in grub-bios-setup grub2-bios-setup; do
        for p in "$t" "/sbin/$t" "/usr/sbin/$t" "/usr/local/sbin/$t"; do
            command -v "$p" >/dev/null 2>&1 && { BIOS_SETUP="$p"; return 0; }
        done
    done
    # Debian-style unshimmed layout
    for p in /usr/lib/grub/i386-pc/grub-bios-setup \
             /usr/lib/grub/i386-pc/grub2-bios-setup \
             /usr/lib/grub2/i386-pc/grub-bios-setup; do
        [ -x "$p" ] && { BIOS_SETUP="$p"; return 0; }
    done
    return 1
}

# Verify grub-pc-bin (BIOS) and grub-efi tooling are available. Without
# these the installer would silently skip BIOS boot setup, leaving a
# UEFI-only device with no warning. Prompt the user to install if missing.
check_boot_tools() {
    locate_bios_setup

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

        offer_install "grub-bios-setup (BIOS boot support)" "${pkgs[@]}" || true

        locate_bios_setup

        # Offline fallback: extract the bundled .deb payload. Runs
        # automatically if the package manager attempt did not produce
        # the binary. Silent on failure - we fall through to the same
        # UEFI-only confirmation prompt as before.
        if [ -z "$BIOS_SETUP" ]; then
            warn "grub-bios-setup not available from the package manager."
            info "Attempting offline install from bundled .deb..."
            extract_bundled_grub || true
        fi

        if [ -z "$BIOS_SETUP" ]; then
            warn "grub-bios-setup still not available."
            warn "Device will boot in ${BOLD}UEFI mode only${NC}${YLW}. BIOS/legacy boot will not work.${NC}"
            echo
            local a
            if [ "$GUI_MODE" = "1" ]; then
                # GUI needs to prompt the user explicitly - abort here and
                # let the wrapper re-launch with the user's answer.
                echo "PICK: uefi_only_continue"
                die "GUI: user confirmation required for UEFI-only install"
            else
                read -rp "  Continue with UEFI-only install? [${GRN}y${NC}/${RED}N${NC}]: " a
                [[ "$a" =~ ^[Yy]$ ]] || die "aborted - install grub-pc-bin and re-run"
            fi
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

    # Now that the clone is available, prefer its Gdisk-Installer
    # directory for offline bundle lookups (Gdisk-Efi.tar.xz.sh,
    # grub-pc-efi.tar.xz.sh) - the installer script itself may have
    # been fetched to /tmp via wget without those files.
    resolve_installer_dir
}

# ====================================================================
#  DEVICE / PARTITION PICKERS
# ====================================================================
pick_disk() {
    if [ "$GUI_MODE" = "1" ]; then
        [ -n "$GUI_DISK" ] || die "GUI mode: --disk is required for this operation"
        [ -b "$GUI_DISK" ] || die "not a block device: $GUI_DISK"
        REPLY_DISK="$GUI_DISK"
        info "Target disk: $REPLY_DISK"
        return 0
    fi
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
    if [ "$GUI_MODE" = "1" ]; then
        [ -n "$GUI_PART" ] || die "GUI mode: --part is required for this operation"
        [ -b "$GUI_PART" ] || die "not a block device: $GUI_PART"
        REPLY_PART="$GUI_PART"
        info "Target partition: $REPLY_PART"
        return 0
    fi
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
    if [ "$GUI_MODE" = "1" ]; then
        # GUI already showed its own destructive-op confirmation dialog
        # before invoking us. Just announce and proceed.
        warn "ALL DATA on $tgt will be DESTROYED (confirmed via GUI)"
        return 0
    fi
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

# Ensure the pre-built EFI disk image is on disk and return its path
# via echo. The image is a 20 MB MBR disk with a single FAT16 boot
# partition containing the full Gdisk EFI/ tree - a verified-bootable
# artefact that we dd onto the target to skip all the fragile
# partition-table + format + copy sequencing for the ESP.
#
# Ships as Gdisk_Efi-20MB.img packed inside Gdisk-Efi.tar.xz, which
# itself is a self-extracting base64 script (Gdisk-Efi.tar.xz.sh) to
# survive text-only transports.
# Stable staging dir for the extracted EFI image. Idempotent - if the
# image is already extracted here from a prior call in this run, we
# reuse it.
EFI_IMG_STAGE="/tmp/gdisk-efi-image-$$"
ensure_efi_image() {
    local stagedir="$EFI_IMG_STAGE"
    local img="$stagedir/Gdisk_Efi-20MB.img"

    # Idempotent fast path
    if [ -f "$img" ]; then
        echo "$img"; return 0
    fi

    local rebuild_sh="$INSTALLER_DIR/Gdisk-Efi.tar.xz.sh"
    local bundle="$INSTALLER_DIR/Gdisk-Efi.tar.xz"
    mkdir -p "$stagedir"

    if [ ! -f "$bundle" ]; then
        [ -f "$rebuild_sh" ] || die "missing Gdisk-Efi.tar.xz(.sh) beside installer"
        # Rebuild only if we haven't already staged the tarball here
        if [ ! -f "$stagedir/Gdisk-Efi.tar.xz" ]; then
            info "Rebuilding pre-built EFI image archive..." >&2
            ( cd "$stagedir" && cp "$rebuild_sh" . && \
              bash "$(basename "$rebuild_sh")" </dev/null >/dev/null 2>&1 ) \
                || die "Gdisk-Efi.tar.xz rebuild failed"
        fi
        bundle="$stagedir/Gdisk-Efi.tar.xz"
    fi

    info "Extracting Gdisk_Efi-20MB.img..." >&2
    tar -xJf "$bundle" -C "$stagedir" \
        || die "Gdisk-Efi.tar.xz extract failed"

    [ -f "$img" ] || die "Gdisk_Efi-20MB.img not found in bundle"
    echo "$img"
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

            local efi_img; efi_img="$(ensure_efi_image)"
            local efi_bytes; efi_bytes="$(stat -c%s "$efi_img")"
            local efi_mib=$(( efi_bytes / 1024 / 1024 ))
            [ "$efi_mib" -gt 0 ] || die "EFI image size invalid: $efi_bytes bytes"

            msg "Writing pre-built EFI image (${HL}${efi_mib} MiB${NC}) to ${HL}${disk}${NC}"
            # NOTE: this dd runs BEFORE the mklabel above (which happens
            # at function entry). We already wiped and zeroed the first
            # 8 MiB and wrote an msdos label. Overwrite everything with
            # the pre-built image now - it brings its own MBR + boot
            # flag + FAT16 partition table.
            dd if="$efi_img" of="$disk" bs=1M conv=fsync status=none \
                || die "dd of EFI image failed"
            partprobe "$disk"; sleep 1

            # The pre-built image occupies partition 1. Add partition 2
            # starting at the next sector after p1 ends, so there is no
            # unallocated gap between the two. The EFI image is a 20 MiB
            # file whose internal FAT16 partition is only 19 MiB (1 MiB
            # of MBR + alignment at the start), so a naive +1 MiB offset
            # from efi_mib left a visible 1 MiB gap in GParted.
            msg "Creating hybrid layout: FAT16 EFI (pre-built, ${HL}${efi_mib} MiB${NC}) + ${data_fs^^} (${HL}${size_spec}${NC})"

            # Pull the real end of partition 1 from parted's machine
            # output in sectors, convert to a byte-exact start for p2.
            local p1_end_sec sec_size data_start_bytes data_start_sec
            p1_end_sec="$(parted -s -m "$disk" unit s print 2>/dev/null \
                | awk -F: '/^1:/ { s=$3; sub(/s$/,"",s); print s }')"
            sec_size="$(parted -s -m "$disk" unit b print 2>/dev/null \
                | awk -F: 'NR==2 { s=$4; sub(/B$/,"",s); print s }')"
            [ -z "$sec_size" ] && sec_size=512
            if [ -n "$p1_end_sec" ]; then
                data_start_sec=$(( p1_end_sec + 1 ))
            else
                # Fallback to old behaviour if parted output changes
                warn "could not read p1 end from parted - using ${efi_mib}MiB offset"
                data_start_sec=$(( efi_mib * 1024 * 1024 / sec_size ))
            fi
            local data_start_expr="${data_start_sec}s"

            # --align none is critical here: parted's default "optimal"
            # alignment snaps the start up to the next 1 MiB boundary,
            # which produces the 1 MiB unallocated gap between p1 and p2
            # visible in GParted. The sector-exact start we computed is
            # already on a safe boundary (p1 was itself aligned by parted
            # when the pre-built image was built), so align=none is both
            # correct and does not hurt I/O.
            if [ "$size_spec" = "MAX" ]; then
                parted -s -a none "$disk" mkpart primary ntfs "$data_start_expr" 100%
            else
                local end_expr add_mib
                if [[ "$size_spec" =~ ^([0-9]+)[Gg]$ ]]; then
                    add_mib=$(( ${BASH_REMATCH[1]} * 1024 ))
                elif [[ "$size_spec" =~ ^([0-9]+)[Mm]$ ]]; then
                    add_mib="${BASH_REMATCH[1]}"
                else
                    die "invalid size: $size_spec"
                fi
                local end_sec=$(( data_start_sec + add_mib * 1024 * 1024 / sec_size - 1 ))
                end_expr="${end_sec}s"
                parted -s -a none "$disk" mkpart primary ntfs "$data_start_expr" "$end_expr"
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
    local hybrid="${2:-}"    # currently informational; EFI/ is deployed on both partitions in hybrid mode

    mkdir -p "$MNT"
    mount "$main_part" "$MNT" || die "mount $main_part failed"
    msg "Deploying Gdisk files from repo to ${HL}$main_part${NC}"

    # Deploy the full repo tree - INCLUDING EFI/ - to the data
    # partition. The pre-built ESP already carries EFI/ so the firmware
    # can find BOOTX64.EFI without needing to read NTFS/exFAT, but
    # rEFInd / grubfm / iPXE EFI apps also need to be reachable from
    # /EFI/ on the data volume once GRUB is running. Without this the
    # user cannot chain into those tools even though the modules are
    # loaded. The duplication cost is ~10 MB, worth it for the feature.
    rsync -a --exclude='.git' --exclude='.gitignore' --exclude='.gitattributes' \
          --exclude='README.md' --exclude='LICENSE' \
          "$REPO_DIR"/ "$MNT"/ \
        || die "file deployment failed"
    sync

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
    acquire_sources
    check_boot_tools
    check_xz
    pick_disk
    local disk="$REPLY_DISK"
    confirm_destroy "$disk"

    # layout selection
    local L LAYOUT
    if [ "$GUI_MODE" = "1" ]; then
        LAYOUT="$GUI_LAYOUT"
        case "$LAYOUT" in
            fat32)        ;;
            fat32_ntfs)   check_datafs_tools ntfs ;;
            fat32_exfat)  check_datafs_tools exfat ;;
            *) die "GUI mode: invalid --layout '$LAYOUT' (expected fat32|fat32_ntfs|fat32_exfat)" ;;
        esac
        info "Layout: $LAYOUT"
    else
        header "Select Gdisk Filesystem Setup"
        echo "  ${BOLD}1.${NC} ${HL}Pure FAT32${NC}       ~ single FAT32 partition (simplest, 4 GiB file cap)"
        echo "  ${BOLD}2.${NC} ${HL}FAT32 + NTFS${NC}     ~ 32 MB Gdisk-EFI + Gdisk-Ntfs   (${GRN}recommended${NC}, supports VHD native boot)"
        echo "  ${BOLD}3.${NC} ${HL}FAT32 + exFAT${NC}    ~ 32 MB Gdisk-EFI + Gdisk-exFAT  (cross-platform, no VHD native boot)"
        echo
        read -rp "  > " L
        case "$L" in
            1) LAYOUT="fat32" ;;
            2) LAYOUT="fat32_ntfs"  ; check_datafs_tools ntfs ;;
            3) LAYOUT="fat32_exfat" ; check_datafs_tools exfat ;;
            *) die "invalid choice: $L" ;;
        esac
    fi

    # size selection: applies to the (single|data) partition
    local s sz
    if [ "$GUI_MODE" = "1" ]; then
        [ -n "$GUI_SIZESPEC" ] || die "GUI mode: --size is required (MAX or NN[MG])"
        if [ "$GUI_SIZESPEC" = "MAX" ]; then
            SIZESPEC="MAX"
        else
            [[ "$GUI_SIZESPEC" =~ ^[0-9]+[MGmg]$ ]] || die "GUI mode: invalid --size '$GUI_SIZESPEC'"
            SIZESPEC="$GUI_SIZESPEC"
        fi
        info "Partition size: $SIZESPEC"
    else
        header "Partition Size"
        if [ "$LAYOUT" = "fat32" ]; then
            echo "  ${BOLD}FAT32${NC} partition size:"
        else
            echo "  ${BOLD}Data${NC} partition size (the 32 MB ${HL}Gdisk-EFI${NC} partition is fixed):"
        fi
        echo "    ${BOLD}1.${NC} ${HL}Fill entire disk${NC} ~ recommended"
        echo "    ${BOLD}2.${NC} ${HL}Custom size${NC}      ~ e.g. 8G, 16G, 4096M"
        echo
        read -rp "  > " s
        if [ "$s" = "2" ]; then
            echo
            read -rp "  Enter size (e.g. ${HL}8G${NC}): " sz
            [[ "$sz" =~ ^[0-9]+[MGmg]$ ]] || die "invalid size: $sz"
            SIZESPEC="$sz"
        else
            SIZESPEC="MAX"
        fi
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
            format_data_ntfs "$DATA_PART"
            # Main tree goes on NTFS; pre-built EFI image already
            # populated the ESP by dd during make_layout.
            deploy_files "$DATA_PART" hybrid
            # BIOS boot: /boot/grub lives on NTFS, so aim grub-bios-setup there
            install_bios_boot "$disk" "$DATA_PART"
            finalize "$disk" "$DATA_PART"
            ;;
        fat32_exfat)
            format_data_exfat "$DATA_PART"
            deploy_files "$DATA_PART" hybrid
            install_bios_boot "$disk" "$DATA_PART"
            finalize "$disk" "$DATA_PART"
            ;;
    esac
}

op_update() {
    header "Update Gdisk"
    info "UPDATE - install/refresh Gdisk onto an EXISTING partition"
    acquire_sources
    check_boot_tools
    check_xz
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
    if [ "$GUI_MODE" = "1" ]; then
        info "GUI mode: proceeding (confirmation handled by wrapper)"
    else
        read -rp "  Proceed? [${GRN}y${NC}/${RED}N${NC}]: " a
        [[ "$a" =~ ^[Yy]$ ]] || die "aborted"
    fi

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
    acquire_sources
    check_boot_tools
    check_xz
    pick_partition
    local part="$REPLY_PART"
    resolve_parent "$part"

    local r
    if [ "$GUI_MODE" = "1" ]; then
        case "$GUI_REPAIR_TARGET" in
            bios) r=1 ;;
            uefi) r=2 ;;
            both) r=3 ;;
            *) die "GUI mode: invalid --repair-target '$GUI_REPAIR_TARGET' (expected bios|uefi|both)" ;;
        esac
        info "Repair target: $GUI_REPAIR_TARGET"
    else
        header "Repair Target"
        echo "  ${BOLD}1.${NC} ${HL}BIOS${NC} ~ MBR + core.img"
        echo "  ${BOLD}2.${NC} ${HL}UEFI${NC} ~ BOOTX64.EFI + modules"
        echo "  ${BOLD}3.${NC} ${HL}Both${NC} ~ BIOS + UEFI"
        echo
        read -rp "  > " r
    fi

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

op_setup() {
    banner
    info "SETUP - Prepares a Linux system inside a .gdisk virtual disk."

    # Silently install kpartx if missing - no prompt, no offer.
    if ! have kpartx; then
        local pm; pm="$(detect_pm)" \
            || die "no supported package manager to install kpartx"
        pm_refresh
        msg "Installing kpartx..."
        # shellcheck disable=SC2086
        $pm kpartx >/dev/null 2>&1 \
            || die "install of kpartx failed"
        have kpartx || die "kpartx still not available after install"
    fi
    cat > /tmp/.gdiskboot.sh << 'GDISKBOOT'
#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  gdiskboot.sh v0.3                                           ║
# ║  Prepares a Linux system inside a .gdisk virtual disk file   ║
# ║  for booting via Gdisk's GRUB2 bootloader.                   ║
# ║                                                              ║
# ║  Run this INSIDE the guest OS (chroot or booted normally).   ║
# ║  It installs initramfs hooks that create /dev/gdisk0 at      ║
# ║  early boot using device-mapper, with partition devices at   ║
# ║  /dev/gdisk0p1, /dev/gdisk0p2, etc.                          ║
# ║                                                              ║
# ║  License: GPLv3+                                             ║
# ║  https://github.com/GlitchLinux/Gdisk                        ║
# ╚══════════════════════════════════════════════════════════════╝

GDISKBOOT_VERSION="0.3"

# -------------------- styling --------------------
RED=$'\e[0;31m'; GRN=$'\e[0;32m'; YLW=$'\e[1;33m'
CYN=$'\e[0;36m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; NC=$'\e[0m'
MAGENTA=$'\033[38;5;198m'; BRIGHT_GREEN=$'\033[0;96m'

# In GUI mode, suppress ANSI colour sequences so the log pane shows
# clean text. The GUI will colour by prefix instead.
if [ "$GUI_MODE" = "1" ]; then
    RED=""; GRN=""; YLW=""; CYN=""; BOLD=""; DIM=""; NC=""
    MAGENTA=""; BRIGHT_GREEN=""
fi

# semantic shortcuts
HL="$MAGENTA"          # highlight: names, devices, partitions
ACCENT="$CYN"          # section accent
RULE_COLOR="$DIM$CYN"

# thin rule sized to the terminal (falls back to 60 cols)
rule() {
    [ "$GUI_MODE" = "1" ] && return 0
    local w; w="$(tput cols 2>/dev/null || echo 60)"
    [ "$w" -gt 70 ] && w=70
    printf "${RULE_COLOR}%*s${NC}\n" "$w" '' | tr ' ' '-'
}

# In GUI mode every status line gets a machine-readable prefix so the
# wrapper can tag it (colour, severity, step counter). In CLI mode we
# emit the pretty coloured text unchanged.
if [ "$GUI_MODE" = "1" ]; then
    msg()  { echo "MSG: $*"; }
    warn() { echo "WARN: $*"; }
    err()  { echo "ERR: $*" >&2; }
    info() { echo "INFO: $*"; }
    die()  { echo "FAIL: $*" >&2; cleanup; exit 1; }
    header() { echo "STEP: $*"; }
    banner() { echo "STEP: Gdisk v3.2 - Download ~ Install ~ Repair"; }
else
    msg()  { echo -e "${GRN}[+]${NC} $*"; }
    warn() { echo -e "${YLW}[!]${NC} $*"; }
    err()  { echo -e "${RED}[x]${NC} $*"; }
    info() { echo -e "${CYN}[i]${NC} $*"; }
    die()  { err "$*"; cleanup; exit 1; }
    header() {
        clear
        echo
        echo "${CYN} ${BOLD}Gdiskboot v0.3${NC} ❖${NC}${CYN} ${BOLD}$*${NC}"
        echo
    }
    banner() {
        clear
        echo
        echo "${CYN} ${BOLD}Gdisk v3.2${NC} ❖${NC}${CYN} ${BOLD}Download ~ Install ~ Repair ${NC}"
        echo
    }
fi

if [ "$(id -u)" -ne 0 ]; then
    err "Please run this script as root or with sudo"
    exit 1
fi

detect_initramfs_tool() {
    if command -v dracut >/dev/null 2>&1; then echo "dracut"
    elif [ -d /usr/share/initramfs-tools ] && command -v update-initramfs >/dev/null 2>&1; then echo "initramfs-tools"
    elif command -v mkinitcpio >/dev/null 2>&1; then echo "mkinitcpio"
    else echo "unknown"; fi
}

INITRAMFS_TOOL=$(detect_initramfs_tool)
info "Detected initramfs tool: ${INITRAMFS_TOOL}"

if [ "${INITRAMFS_TOOL}" = "unknown" ]; then
    err "No supported initramfs tool found (need dracut, initramfs-tools, or mkinitcpio)"
    exit 1
fi

for tool in dmsetup blkid awk sed grep; do
    command -v "${tool}" >/dev/null 2>&1 || { err "Required tool '${tool}' not found."; exit 1; }
done

command -v kpartx >/dev/null 2>&1 || warn "kpartx not found - install: apt install kpartx"

# ════════════════════════════════════════════════════════════════
#  COMMON BOOT HOOK
# ════════════════════════════════════════════════════════════════

generate_common_hook() {
cat << 'GDISK_HOOK_EOF'
#!/bin/sh
# gdiskboot early-boot hook v0.3
# Creates /dev/gdisk0 and /dev/gdisk0pN from a .gdisk virtual disk file

gdisk_log() {
    echo "gdiskboot: $*" > /dev/kmsg 2>/dev/null
    echo "$*" >> /run/gdisk-boot.log 2>/dev/null
}

gdisk_cmdline_val() {
    local key="$1" val=""
    for param in $(cat /proc/cmdline); do
        case "${param}" in ${key}=*) val="${param#${key}=}" ;; esac
    done
    echo "${val}"
}

GDISK_DEV=$(gdisk_cmdline_val "gdisk.dev")
GDISK_FILE=$(gdisk_cmdline_val "gdisk.file")
GDISK_ROOT=$(gdisk_cmdline_val "gdisk.root")
GDISK_METHOD=$(gdisk_cmdline_val "gdisk.method")

[ -z "${GDISK_DEV}" ] || [ -z "${GDISK_FILE}" ] && exit 0
[ -z "${GDISK_ROOT}" ] && GDISK_ROOT=1
[ -z "${GDISK_METHOD}" ] && GDISK_METHOD="auto"

gdisk_log "Starting gdiskboot"
gdisk_log "  dev=${GDISK_DEV} file=${GDISK_FILE} root=p${GDISK_ROOT} method=${GDISK_METHOD}"

mkdir -p /run/gdisk
[ -e /dev/mapper/gdisk0 ] && { gdisk_log "gdisk0 exists, skipping"; exit 0; }

modprobe -q dm-mod 2>/dev/null || true
modprobe -q loop 2>/dev/null || true
for drv in usb-storage ehci-hcd ehci-pci ohci-hcd ohci-pci \
           xhci-hcd xhci-pci uhci-hcd uas nvme sd_mod \
           ext4 xfs btrfs vfat ntfs3 exfat; do
    modprobe -q "${drv}" 2>/dev/null || true
done

gdisk_log "Waiting for host device: ${GDISK_DEV}"
HOST_BLKDEV=""
WAIT=0
while [ ${WAIT} -lt 60 ]; do
    case "${GDISK_DEV}" in
        UUID=*|LABEL=*|PARTUUID=*) HOST_BLKDEV=$(blkid -t "${GDISK_DEV}" -o device 2>/dev/null | head -1) ;;
        /dev/*) [ -b "${GDISK_DEV}" ] && HOST_BLKDEV="${GDISK_DEV}" ;;
    esac
    [ -n "${HOST_BLKDEV}" ] && [ -b "${HOST_BLKDEV}" ] && break
    sleep 0.5; WAIT=$((WAIT + 1))
done

[ -z "${HOST_BLKDEV}" ] && { gdisk_log "ERROR: ${GDISK_DEV} not found"; exit 1; }
gdisk_log "Host device: ${HOST_BLKDEV}"

HOST_FS=$(blkid -s TYPE -o value "${HOST_BLKDEV}" 2>/dev/null)
gdisk_log "Host filesystem: ${HOST_FS}"
case "${HOST_FS}" in
    ext2|ext3|ext4) modprobe -q ext4 2>/dev/null || true ;;
    xfs)     modprobe -q xfs 2>/dev/null || true ;;
    btrfs)   modprobe -q btrfs 2>/dev/null || true ;;
    ntfs*)   modprobe -q ntfs3 2>/dev/null || true ;;
    vfat)    modprobe -q vfat 2>/dev/null || true ;;
    exfat)   modprobe -q exfat 2>/dev/null || true ;;
esac

mkdir -p /run/gdisk/host
MOUNT_OK=0
mount "${HOST_BLKDEV}" /run/gdisk/host 2>/dev/null && MOUNT_OK=1
[ "${MOUNT_OK}" = "0" ] && mount -o ro "${HOST_BLKDEV}" /run/gdisk/host 2>/dev/null && MOUNT_OK=1
[ "${MOUNT_OK}" = "0" ] && { gdisk_log "ERROR: mount failed"; exit 1; }

GDISK_FULLPATH="/run/gdisk/host${GDISK_FILE}"
[ ! -f "${GDISK_FULLPATH}" ] && { gdisk_log "ERROR: ${GDISK_FILE} not found"; umount /run/gdisk/host 2>/dev/null; exit 1; }

GDISK_SIZE_BYTES=$(stat -c '%s' "${GDISK_FULLPATH}")
GDISK_SIZE_SECTORS=$((GDISK_SIZE_BYTES / 512))
gdisk_log "Image: ${GDISK_FILE} (${GDISK_SIZE_SECTORS} sectors)"

# ── Method selection ───────────────────────────────────────
USE_FIEMAP=0
if [ "${GDISK_METHOD}" = "loop" ]; then
    gdisk_log "Loop method forced"
elif [ "${HOST_FS}" = "ntfs" ] || [ "${HOST_FS}" = "ntfs3" ]; then
    gdisk_log "NTFS - using loop method"
elif [ "${GDISK_METHOD}" = "fiemap" ] || [ "${GDISK_METHOD}" = "auto" ]; then
    if command -v filefrag >/dev/null 2>&1 && filefrag -e -s "${GDISK_FULLPATH}" >/dev/null 2>&1; then
        USE_FIEMAP=1
    fi
fi

get_parent_disk() {
    local short="${1#/dev/}"
    if [ -f "/sys/class/block/${short}/../dev" ]; then
        echo "/dev/$(basename "$(readlink -f "/sys/class/block/${short}/..")")"
    else
        echo "$1" | sed -E 's/p?[0-9]+$//'
    fi
}

if [ "${USE_FIEMAP}" = "1" ]; then
    gdisk_log "Using FIEMAP"
    PARENT_DISK=$(get_parent_disk "${HOST_BLKDEV}")
    PART_START=$(cat "/sys/class/block/${HOST_BLKDEV#/dev/}/start" 2>/dev/null || echo 0)

    filefrag -e -s "${GDISK_FULLPATH}" 2>/dev/null | grep -E '^\s+[0-9]+:' | \
    while IFS= read -r line; do
        PHYS=$(echo "${line}" | awk -F: '{print $3}' | awk -F'.' '{print $1}' | tr -d ' ')
        LEN=$(echo "${line}" | awk -F: '{print $4}' | awk -F'.' '{print $1}' | tr -d ' ')
        [ -n "${PHYS}" ] && [ -n "${LEN}" ] && [ "${LEN}" -gt 0 ] 2>/dev/null && \
            echo "0 ${LEN} linear ${PARENT_DISK} $((PHYS + PART_START))"
    done > /run/gdisk/dm-table

    if [ -s /run/gdisk/dm-table ]; then
        TABLE_S=$(awk '{sum+=$2}END{print int(sum)}' /run/gdisk/dm-table)
        DIFF=$((GDISK_SIZE_SECTORS - TABLE_S)); [ "${DIFF}" -lt 0 ] && DIFF=$((-DIFF))
        if [ "${DIFF}" -gt 1024 ]; then
            gdisk_log "FIEMAP incomplete (${TABLE_S}/${GDISK_SIZE_SECTORS}) - fallback to loop"
            USE_FIEMAP=0; rm -f /run/gdisk/dm-table
        fi
    else
        USE_FIEMAP=0
    fi

    if [ "${USE_FIEMAP}" = "1" ]; then
        umount /run/gdisk/host 2>/dev/null || true
        dmsetup create gdisk0 /run/gdisk/dm-table || {
            gdisk_log "dmsetup failed - fallback to loop"; USE_FIEMAP=0
            mount "${HOST_BLKDEV}" /run/gdisk/host 2>/dev/null || mount -o ro "${HOST_BLKDEV}" /run/gdisk/host 2>/dev/null
        }
    fi
fi

if [ "${USE_FIEMAP}" = "0" ]; then
    gdisk_log "Using loop method"
    # BusyBox losetup doesn't support --show, use two-step
    LOOP_DEV=$(losetup -f 2>/dev/null)
    if [ -z "${LOOP_DEV}" ]; then
        gdisk_log "ERROR: no free loop device"; umount /run/gdisk/host 2>/dev/null; exit 1
    fi
    if ! losetup "${LOOP_DEV}" "${GDISK_FULLPATH}" 2>/dev/null; then
        gdisk_log "ERROR: losetup ${LOOP_DEV} failed for ${GDISK_FULLPATH}"; umount /run/gdisk/host 2>/dev/null; exit 1
    fi
    gdisk_log "Loop: ${LOOP_DEV}"
    LOOP_SHORT="${LOOP_DEV#/dev/}"
    LOOP_SECTORS=$(cat "/sys/class/block/${LOOP_SHORT}/size" 2>/dev/null)
    [ -z "${LOOP_SECTORS}" ] || [ "${LOOP_SECTORS}" = "0" ] && LOOP_SECTORS=$((GDISK_SIZE_BYTES / 512))
    echo "0 ${LOOP_SECTORS} linear ${LOOP_DEV} 0" | dmsetup create gdisk0 || {
        gdisk_log "ERROR: dmsetup failed"; losetup -d "${LOOP_DEV}" 2>/dev/null; umount /run/gdisk/host 2>/dev/null; exit 1
    }
fi

WAIT=0
while [ ! -e /dev/mapper/gdisk0 ] && [ ${WAIT} -lt 20 ]; do sleep 0.25; WAIT=$((WAIT+1)); done
[ ! -e /dev/mapper/gdisk0 ] && { gdisk_log "ERROR: gdisk0 missing"; exit 1; }
ln -sf /dev/mapper/gdisk0 /dev/gdisk0 2>/dev/null || true

gdisk_log "Discovering partitions..."
if command -v kpartx >/dev/null 2>&1; then
    if [ -n "${LOOP_DEV}" ] && [ -b "${LOOP_DEV}" ]; then
        KPARTX_TARGET="${LOOP_DEV}"; KPARTX_PREFIX="${LOOP_SHORT}"
    else
        KPARTX_TARGET="/dev/mapper/gdisk0"; KPARTX_PREFIX="gdisk0"
    fi
    kpartx -a "${KPARTX_TARGET}" 2>/dev/null; sleep 0.5
    for dmpart in /dev/mapper/${KPARTX_PREFIX}p*; do
        if [ -b "${dmpart}" ]; then
            PNUM="${dmpart##*${KPARTX_PREFIX}p}"
            if [ "${KPARTX_PREFIX}" != "gdisk0" ]; then
                PTABLE=$(dmsetup table "${KPARTX_PREFIX}p${PNUM}" 2>/dev/null)
                [ -n "${PTABLE}" ] && echo "${PTABLE}" | dmsetup create "gdisk0p${PNUM}" 2>/dev/null
            fi
            ln -sf "/dev/mapper/gdisk0p${PNUM}" "/dev/gdisk0p${PNUM}" 2>/dev/null || true
            gdisk_log "Partition: /dev/gdisk0p${PNUM}"
        fi
    done
elif command -v sfdisk >/dev/null 2>&1; then
    PNUM=0
    sfdisk -d /dev/mapper/gdisk0 2>/dev/null | grep -E '^/dev/' | while IFS= read -r line; do
        PNUM=$((PNUM+1))
        P_START=$(echo "${line}" | sed -n 's/.*start=\s*\([0-9]*\).*/\1/p')
        P_SIZE=$(echo "${line}" | sed -n 's/.*size=\s*\([0-9]*\).*/\1/p')
        [ -n "${P_START}" ] && [ -n "${P_SIZE}" ] && [ "${P_SIZE}" -gt 0 ] && \
            echo "0 ${P_SIZE} linear /dev/mapper/gdisk0 ${P_START}" | dmsetup create "gdisk0p${PNUM}" 2>/dev/null && \
            ln -sf "/dev/mapper/gdisk0p${PNUM}" "/dev/gdisk0p${PNUM}" 2>/dev/null || true
    done
fi

if [ -b "/dev/mapper/gdisk0p${GDISK_ROOT}" ]; then
    gdisk_log "Root: /dev/gdisk0p${GDISK_ROOT}"
else
    gdisk_log "WARNING: /dev/gdisk0p${GDISK_ROOT} not found"
fi
gdisk_log "gdiskboot complete"
GDISK_HOOK_EOF
}


# ════════════════════════════════════════════════════════════════
#  UDEV RULES
# ════════════════════════════════════════════════════════════════

install_udev_rules() {
    cat > "$1" << 'EOF'
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0",   SYMLINK+="gdisk0",   OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p1",  SYMLINK+="gdisk0p1",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p2",  SYMLINK+="gdisk0p2",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p3",  SYMLINK+="gdisk0p3",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p4",  SYMLINK+="gdisk0p4",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p5",  SYMLINK+="gdisk0p5",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p6",  SYMLINK+="gdisk0p6",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p7",  SYMLINK+="gdisk0p7",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p8",  SYMLINK+="gdisk0p8",  OPTIONS+="link_priority=100"
EOF
}


# ════════════════════════════════════════════════════════════════
#  INSTALL: DRACUT
# ════════════════════════════════════════════════════════════════

install_dracut() {
    info "Installing dracut module..."
    local MODDIR
    for d in /usr/lib/dracut/modules.d /lib/dracut/modules.d; do
        [ -d "${d}" ] && MODDIR="${d}/99gdisk" && break
    done
    [ -z "${MODDIR}" ] && { err "dracut modules dir not found"; return 1; }
    mkdir -p /etc/dracut.conf.d
    rm -rf "${MODDIR}"; mkdir -p "${MODDIR}"

    cat > "${MODDIR}/module-setup.sh" << 'EOF'
#!/bin/bash
check() { require_binaries dmsetup blkid awk sed grep || return 1; return 255; }
depends() { echo dm; return 0; }
install() {
    inst_multiple dmsetup blkid awk sed grep dd stat losetup ln sleep cat mkdir mount umount modprobe
    for t in kpartx filefrag sfdisk partprobe blockdev; do
        command -v "$t" >/dev/null 2>&1 && inst_multiple "$t"
    done
    inst_hook initqueue/settled 90 "$moddir/gdisk-settled.sh"
    inst_simple "$moddir/gdisk-udev.rules" /etc/udev/rules.d/99-gdisk.rules
    dracut_need_initqueue
}
EOF
    chmod +x "${MODDIR}/module-setup.sh"
    generate_common_hook > "${MODDIR}/gdisk-settled.sh"; chmod +x "${MODDIR}/gdisk-settled.sh"
    install_udev_rules "${MODDIR}/gdisk-udev.rules"
    echo 'add_dracutmodules+=" gdisk "
force_drivers+=" dm-mod loop "' > /etc/dracut.conf.d/gdisk.conf
    ok "Dracut module installed"
}


# ════════════════════════════════════════════════════════════════
#  INSTALL: INITRAMFS-TOOLS
# ════════════════════════════════════════════════════════════════

install_initramfs_tools() {
    info "Installing initramfs-tools hooks..."
    cat > /usr/share/initramfs-tools/hooks/gdisk << 'EOF'
#!/bin/sh
PREREQ="dmsetup"
prereqs() { echo "$PREREQ"; }
case $1 in prereqs) prereqs; exit 0 ;; esac
. /usr/share/initramfs-tools/hook-functions
for tool in dmsetup blkid awk sed grep dd stat losetup ln sleep cat mkdir mount umount modprobe; do
    for p in /bin /sbin /usr/bin /usr/sbin; do [ -f "$p/$tool" ] && copy_exec "$p/$tool" /sbin && break; done
done
for tool in kpartx filefrag sfdisk partprobe blockdev; do
    for p in /bin /sbin /usr/bin /usr/sbin; do [ -f "$p/$tool" ] && copy_exec "$p/$tool" /sbin && break; done
done
force_load dm-mod; force_load loop
[ -f /etc/udev/rules.d/99-gdisk.rules ] && mkdir -p "$DESTDIR/etc/udev/rules.d" && cp /etc/udev/rules.d/99-gdisk.rules "$DESTDIR/etc/udev/rules.d/"
EOF
    chmod +x /usr/share/initramfs-tools/hooks/gdisk
    generate_common_hook > /etc/initramfs-tools/scripts/local-top/gdisk
    chmod +x /etc/initramfs-tools/scripts/local-top/gdisk
    install_udev_rules /etc/udev/rules.d/99-gdisk.rules
    ok "initramfs-tools hooks installed"
}


# ════════════════════════════════════════════════════════════════
#  INSTALL: MKINITCPIO
# ════════════════════════════════════════════════════════════════

install_mkinitcpio() {
    info "Installing mkinitcpio hooks..."
    cat > /usr/lib/initcpio/install/gdisk << 'EOF'
#!/bin/bash
build() {
    for b in dmsetup blkid awk sed grep dd stat losetup ln sleep cat mkdir mount umount modprobe; do add_binary "$b"; done
    for t in kpartx filefrag sfdisk partprobe blockdev; do command -v "$t" >/dev/null 2>&1 && add_binary "$t"; done
    add_module dm-mod; add_module loop; add_file /etc/udev/rules.d/99-gdisk.rules; add_runscript
}
help() { echo "Gdisk virtual disk boot support."; }
EOF
    chmod +x /usr/lib/initcpio/install/gdisk
    generate_common_hook > /usr/lib/initcpio/hooks/gdisk; chmod +x /usr/lib/initcpio/hooks/gdisk
    install_udev_rules /etc/udev/rules.d/99-gdisk.rules
    [ -f /etc/mkinitcpio.conf ] && ! grep -q 'gdisk' /etc/mkinitcpio.conf && \
        warn "Add 'gdisk' to HOOKS in /etc/mkinitcpio.conf (after block, before filesystems)"
    ok "mkinitcpio hooks installed"
}


# ════════════════════════════════════════════════════════════════
#  GRUB-PROBE WRAPPER
# ════════════════════════════════════════════════════════════════

install_grub_fixup() {
    info "Installing GRUB fixup..."
    local PROBE=""
    command -v grub-probe >/dev/null 2>&1 && PROBE=$(command -v grub-probe)
    [ -z "$PROBE" ] && command -v grub2-probe >/dev/null 2>&1 && PROBE=$(command -v grub2-probe)
    [ -z "$PROBE" ] && { warn "grub-probe not found"; return 0; }
    [ -f "${PROBE}-bk" ] && grep -q 'gdiskboot' "$PROBE" 2>/dev/null && { info "Already installed"; return 0; }
    [ -f "${PROBE}-bk" ] && mv "${PROBE}-bk" "$PROBE"
    cp -a "$PROBE" "${PROBE}-bk"
    cat > "$PROBE" << 'W'
#!/bin/sh
# gdiskboot grub-probe wrapper
R="${0}-bk"; O=$("$R" "$@" 2>/tmp/gpe); E=$?
[ $E -eq 0 ] && echo "$O" && exit 0
echo "$@" | grep -q '/dev/gdisk0\|/dev/mapper/gdisk0' && {
case "$@" in
*--target=device*) echo /dev/gdisk0; exit 0;;
*--target=fs*) for p in /dev/gdisk0p1 /dev/mapper/gdisk0p1; do [ -b "$p" ] && F=$(blkid -s TYPE -o value "$p" 2>/dev/null) && [ -n "$F" ] && echo "$F" && exit 0; done; echo ext2; exit 0;;
*--target=fs_uuid*) for p in /dev/gdisk0p1 /dev/mapper/gdisk0p1; do [ -b "$p" ] && U=$(blkid -s UUID -o value "$p" 2>/dev/null) && [ -n "$U" ] && echo "$U" && exit 0; done;;
*--target=drive*) echo "(gdisk0)"; exit 0;;
*--target=abstraction*) echo ""; exit 0;;
*--target=partmap*) echo msdos; exit 0;;
esac; }
cat /tmp/gpe >&2; exit $E
W
    chmod +x "$PROBE"
    ok "GRUB probe wrapper installed"
}


# ════════════════════════════════════════════════════════════════
#  UNINSTALL
# ════════════════════════════════════════════════════════════════

uninstall_gdiskboot() {
    info "Uninstalling gdiskboot..."
    for d in /usr/lib/dracut/modules.d/99gdisk /lib/dracut/modules.d/99gdisk; do [ -d "$d" ] && rm -rf "$d"; done
    rm -f /etc/dracut.conf.d/gdisk.conf 2>/dev/null
    rm -f /usr/share/initramfs-tools/hooks/gdisk /etc/initramfs-tools/scripts/local-top/gdisk 2>/dev/null
    rm -f /usr/lib/initcpio/install/gdisk /usr/lib/initcpio/hooks/gdisk 2>/dev/null
    rm -f /etc/udev/rules.d/99-gdisk.rules 2>/dev/null
    for probe in grub-probe grub2-probe; do
        p=$(command -v "$probe" 2>/dev/null)
        [ -n "$p" ] && [ -f "${p}-bk" ] && grep -q 'gdiskboot' "$p" 2>/dev/null && mv "${p}-bk" "$p"
    done
    ok "Uninstalled. Rebuild initramfs: dracut -f / update-initramfs -u / mkinitcpio -P"
}


# ════════════════════════════════════════════════════════════════
#  REBUILD INITRAMFS
# ════════════════════════════════════════════════════════════════

rebuild_initramfs() {
    info "Rebuilding initramfs..."
    case "${INITRAMFS_TOOL}" in
        dracut)
            dracut -f --no-hostonly
            for k in /lib/modules/*/; do
                kn=$(basename "$k")
                [ "$kn" != "$(uname -r)" ] && [ -d "/lib/modules/${kn}/kernel" ] && dracut -f --no-hostonly --kver "$kn"
            done ;;
        initramfs-tools) update-initramfs -u -k all ;;
        mkinitcpio) mkinitcpio -P ;;
    esac
    ok "Initramfs rebuilt"
}


# ════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════
clear
echo ""
echo "${CYN} ${BOLD}Gdiskboot v0.3${NC} ❖${NC}${CYN} ${BOLD}$*${NC}"
echo ""

case "${1}" in
    -u|--uninstall) uninstall_gdiskboot; rebuild_initramfs; exit 0 ;;
    -h|--help)
        echo "Usage: gdiskboot.sh [OPTIONS]"
        echo "  -u, --uninstall   Remove gdiskboot and restore originals"
        echo "  -s, --skip-grub   Skip GRUB probe wrapper"
        echo "  -h, --help        Show this help"
        echo ""
        echo "Devices after boot:"
        echo "  /dev/gdisk0       Whole virtual disk"
        echo "  /dev/gdisk0p1..N  Partitions"
        exit 0 ;;
esac

SKIP_GRUB=0
for arg in "$@"; do [ "$arg" = "-s" ] || [ "$arg" = "--skip-grub" ] && SKIP_GRUB=1; done

case "${INITRAMFS_TOOL}" in
    dracut)          install_dracut ;;
    initramfs-tools) install_initramfs_tools ;;
    mkinitcpio)      install_mkinitcpio ;;
esac

[ "${SKIP_GRUB}" -eq 0 ] && install_grub_fixup
rebuild_initramfs

echo ""
ok "gdiskboot v${GDISKBOOT_VERSION} installed!"
info "Devices after boot: /dev/gdisk0, /dev/gdisk0p1.."
echo ""

GDISKBOOT
clear
sudo bash /tmp/.gdiskboot.sh
sudo rm /tmp/.gdiskboot.sh
read -p ' '
wget -O /tmp/gdisk-installer -q https://raw.githubusercontent.com/GlitchLinux/Gdisk/refs/heads/main/boot/Gdisk-Installer/gdisk-v3-installer.sh
clear 
sudo bash /tmp/gdisk-installer

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
    if [ "$GUI_MODE" = "1" ]; then
        echo "DONE: Gdisk v3.1 is ready on $disk ($part)"
    fi
}

# ====================================================================
#  MENU
# ====================================================================
if [ "$GUI_MODE" = "1" ]; then
    case "$GUI_OP" in
        create) op_create ;;
        update) op_update ;;
        repair) op_repair ;;
        *) die "GUI mode: --op must be create|update|repair (got '$GUI_OP')" ;;
    esac
    exit 0
fi

banner
echo "  ${BOLD}Select Gdisk Operation [1-4]:${NC}"
echo
echo "  ${BOLD}1.${NC} ${MAGENTA}Create Gdisk${NC} ~ Make a new Gdisk Device"
echo "  ${BOLD}2.${NC} ${MAGENTA}Update Gdisk${NC} ~ Update or Install on existing partition."
echo "  ${BOLD}3.${NC} ${MAGENTA}Repair Gdisk${NC} ~ Fix MBR & UEFI Boot on existing Gdisk device."
echo "  ${BOLD}4.${NC} ${MAGENTA}Setup .Gdisk${NC} ~ Prepares Linux system inside a .gdisk virtual disk."
echo
read -rp "  > " CHOICE
echo

case "$CHOICE" in
    1) op_create ;;
    2) op_update ;;
    3) op_repair ;;
    4) op_setup ;;
    *) die "invalid choice: $CHOICE" ;;
esac
