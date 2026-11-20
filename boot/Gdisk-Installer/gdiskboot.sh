#!/usr/bin/env bash
# =============================================================================
#  gdiskboot-installer.sh                                        gdiskboot 0.5
# -----------------------------------------------------------------------------
#  Run this INSIDE the Linux system that is installed on a .gdisk virtual disk.
#
#  It makes that system bootable by Gdisk: when Gdisk's gdisk-preboot.cfg loads
#  the kernel/initrd straight out of the .gdisk and passes gdisk.dev / gdisk.file
#  / gdisk.root (and, for encrypted hosts, gdisk.luks / gdisk.luksuuid) on the
#  kernel command line, the early-boot hook installed here rebuilds the backing
#  file into /dev/gdisk0 + /dev/gdisk0pN so the normal initramfs can mount root.
#
#  What it does:
#    1. Installs any missing dependencies (device-mapper, cryptsetup, kpartx,
#       e2fsprogs, util-linux) using the distro's package manager.
#    2. Detects the initramfs generator (dracut / initramfs-tools / mkinitcpio).
#    3. Installs the gdiskboot early hook + udev rules into that generator,
#       bundling cryptsetup + dm-crypt so LUKS-hosted images can self-unlock.
#    4. Installs a grub-probe wrapper so grub run inside the guest copes with
#       the /dev/gdisk0 device.
#    5. Rebuilds the initramfs.
#
#  Safe to re-run. Must be run as root.
# =============================================================================

set -u

GDISKBOOT_VERSION="0.5"

# --- pretty output ----------------------------------------------------------
if [ -t 1 ]; then
    BOLD=$'\e[1m'; RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYA=$'\e[36m'; NC=$'\e[0m'
else
    BOLD=""; RED=""; GRN=""; YEL=""; CYA=""; NC=""
fi
msg(){  echo "${CYA}==>${NC} $*"; }
ok(){   echo "${GRN}OK:${NC} $*"; }
warn(){ echo "${YEL}!!${NC} $*" >&2; }
err(){  echo "${RED}ERROR:${NC} $*" >&2; }
die(){  err "$*"; exit 1; }
header(){ echo; echo "${BOLD}${CYA}== $* ==${NC}"; }

[ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)."

header "gdiskboot installer v${GDISKBOOT_VERSION}"

# =============================================================================
#  1. Package manager + dependencies
# =============================================================================
PM=""
for c in apt-get dnf yum pacman zypper apk; do
    command -v "$c" >/dev/null 2>&1 && { PM="$c"; break; }
done
[ -n "$PM" ] || warn "no known package manager found - skipping dependency install"
[ -n "$PM" ] && msg "Package manager: ${PM}"

# Map a required command to its package name for the active PM.
pkg_for() {
    # $1 = command, prints package name (empty = cannot map / skip)
    case "$1" in
        dmsetup)
            case "$PM" in apt-get) echo dmsetup ;; *) echo device-mapper ;; esac ;;
        cryptsetup)
            case "$PM" in apt-get) echo cryptsetup ;; *) echo cryptsetup ;; esac ;;
        kpartx)
            case "$PM" in
                apt-get|dnf|yum|zypper) echo kpartx ;;
                pacman|apk)             echo multipath-tools ;;
                *)                      echo kpartx ;;
            esac ;;
        filefrag)        echo e2fsprogs ;;
        blkid|losetup|blockdev|partprobe) echo util-linux ;;
        *) echo "" ;;
    esac
}

pm_install() {
    # install the given packages with the active PM
    [ "$#" -gt 0 ] || return 0
    case "$PM" in
        apt-get) DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        dnf)     dnf install -y "$@" ;;
        yum)     yum install -y "$@" ;;
        pacman)  pacman -S --needed --noconfirm "$@" ;;
        zypper)  zypper --non-interactive install "$@" ;;
        apk)     apk add "$@" ;;
        *)       return 1 ;;
    esac
}

pm_refresh() {
    case "$PM" in
        apt-get) msg "Refreshing apt index..."; apt-get update -y >/dev/null 2>&1 || true ;;
        apk)     apk update >/dev/null 2>&1 || true ;;
        *) : ;;
    esac
}

# Runtime commands the early hook needs. blkid/losetup are in util-linux and
# almost always present; cryptsetup/kpartx/filefrag often are not.
NEED_CMDS="dmsetup blkid losetup cryptsetup kpartx filefrag"

if [ -n "$PM" ]; then
    MISSING_PKGS=""
    for cmd in $NEED_CMDS; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            p="$(pkg_for "$cmd")"
            [ -n "$p" ] && case " $MISSING_PKGS " in *" $p "*) : ;; *) MISSING_PKGS="$MISSING_PKGS $p" ;; esac
            [ -n "$p" ] && msg "Missing '${cmd}' -> will install '${p}'"
        fi
    done
    # shellcheck disable=SC2086
    if [ -n "${MISSING_PKGS# }" ]; then
        pm_refresh
        msg "Installing:${MISSING_PKGS}"
        pm_install $MISSING_PKGS || warn "package install reported errors - continuing, will re-check"
    else
        ok "All runtime dependencies already present."
    fi
fi

# Hard-require the essentials; kpartx/filefrag are optional (sfdisk fallback).
command -v dmsetup   >/dev/null 2>&1 || die "dmsetup still missing (install device-mapper)."
command -v blkid     >/dev/null 2>&1 || die "blkid still missing (install util-linux)."
command -v losetup   >/dev/null 2>&1 || die "losetup still missing (install util-linux)."
command -v cryptsetup >/dev/null 2>&1 || warn "cryptsetup missing - LUKS-hosted .gdisk images will not self-unlock."
command -v kpartx    >/dev/null 2>&1 || warn "kpartx missing - will fall back to sfdisk for partition discovery."

# =============================================================================
#  2. Detect the initramfs generator
# =============================================================================
INITRAMFS_TOOL=""
if command -v dracut >/dev/null 2>&1 && [ -d /usr/lib/dracut ] 2>/dev/null; then
    INITRAMFS_TOOL="dracut"
elif command -v dracut >/dev/null 2>&1 && [ -d /lib/dracut ] 2>/dev/null; then
    INITRAMFS_TOOL="dracut"
elif [ -d /usr/share/initramfs-tools ] && command -v update-initramfs >/dev/null 2>&1; then
    INITRAMFS_TOOL="initramfs-tools"
elif command -v mkinitcpio >/dev/null 2>&1; then
    INITRAMFS_TOOL="mkinitcpio"
fi

if [ -z "$INITRAMFS_TOOL" ] && [ -n "$PM" ]; then
    warn "No initramfs generator found - attempting to install one."
    case "$PM" in
        apt-get)        pm_install initramfs-tools && INITRAMFS_TOOL="initramfs-tools" ;;
        dnf|yum|zypper) pm_install dracut && INITRAMFS_TOOL="dracut" ;;
        pacman)         pm_install mkinitcpio && INITRAMFS_TOOL="mkinitcpio" ;;
    esac
fi
[ -n "$INITRAMFS_TOOL" ] || die "No supported initramfs tool (need dracut, initramfs-tools, or mkinitcpio)."
msg "Initramfs generator: ${INITRAMFS_TOOL}"

# =============================================================================
#  3. The early-boot hook (written into the chosen generator below)
#     This is the script that runs in the initramfs and builds /dev/gdisk0.
# =============================================================================
_gdiskboot_generate_hook() {
cat << 'GDISK_HOOK_EOF'
#!/bin/sh
# gdiskboot early-boot hook v0.5
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
GDISK_LUKS=$(gdisk_cmdline_val "gdisk.luks")
GDISK_LUKSUUID=$(gdisk_cmdline_val "gdisk.luksuuid")

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
# An encrypted host cannot expose its inner UUID until we unlock the
# container below, so don't burn the full 30s waiting for it to appear.
WAIT_MAX=60
[ "${GDISK_LUKS}" = "1" ] && WAIT_MAX=6
while [ ${WAIT} -lt ${WAIT_MAX} ]; do
    case "${GDISK_DEV}" in
        UUID=*|LABEL=*|PARTUUID=*) HOST_BLKDEV=$(blkid -t "${GDISK_DEV}" -o device 2>/dev/null | head -1) ;;
        /dev/*) [ -b "${GDISK_DEV}" ] && HOST_BLKDEV="${GDISK_DEV}" ;;
    esac
    [ -n "${HOST_BLKDEV}" ] && [ -b "${HOST_BLKDEV}" ] && break
    sleep 0.5; WAIT=$((WAIT + 1))
done

# --- LUKS-encrypted host support --------------------------------------------
# If the .gdisk lives on a LUKS volume (flagged by gdisk.luks=1 from GRUB,
# which already unlocked it to load the kernel), the inner filesystem is
# invisible here until we open the container ourselves. Unlock it, then the
# decrypted volume exposes the UUID the wait loop was looking for. Needs
# cryptsetup + dm-crypt in the initramfs.
if [ -z "${HOST_BLKDEV}" ] && [ "${GDISK_LUKS}" = "1" ]; then
    if command -v cryptsetup >/dev/null 2>&1; then
        gdisk_log "Host is LUKS-encrypted - unlocking container"
        modprobe -q dm-crypt 2>/dev/null || modprobe -q dm_crypt 2>/dev/null || true
        for cm in aes xts sha256 sha512 aes_generic libaes; do
            modprobe -q "${cm}" 2>/dev/null || true
        done

        # Enumerate LUKS containers (util-linux blkid -t, with a portable
        # fallback for busybox blkid).
        LUKS_DEVS=$(blkid -t TYPE=crypto_LUKS -o device 2>/dev/null)
        if [ -z "${LUKS_DEVS}" ]; then
            LUKS_DEVS=$(for d in $(blkid -o device 2>/dev/null); do
                [ "$(blkid -s TYPE -o value "${d}" 2>/dev/null)" = "crypto_LUKS" ] && echo "${d}"
            done)
        fi

        # If GRUB passed the container UUID, try that one first
        # (dash- and case-insensitive compare).
        WANT_UUID=$(echo "${GDISK_LUKSUUID}" | tr -d - | tr 'A-F' 'a-f')
        LUKS_CANDS=""
        for dev in ${LUKS_DEVS}; do
            if [ -n "${WANT_UUID}" ]; then
                HAVE_UUID=$(cryptsetup luksUUID "${dev}" 2>/dev/null | tr -d - | tr 'A-F' 'a-f')
                if [ "${HAVE_UUID}" = "${WANT_UUID}" ]; then
                    LUKS_CANDS="${dev} ${LUKS_CANDS}"
                    continue
                fi
            fi
            LUKS_CANDS="${LUKS_CANDS} ${dev}"
        done

        GDISK_LUKS_MAP="gdiskhost"
        for cand in ${LUKS_CANDS}; do
            [ -b "${cand}" ] || continue
            gdisk_log "Trying LUKS container: ${cand}"

            # 1) Keyfile first (no prompt). GRUB injects the volume's own
            #    unlock key at /gdisk-host.key when it has one, so the user is
            #    not asked for the passphrase a second time.
            if [ ! -b "/dev/mapper/${GDISK_LUKS_MAP}" ] && [ -f /gdisk-host.key ]; then
                if cryptsetup open --key-file /gdisk-host.key "${cand}" "${GDISK_LUKS_MAP}" >/dev/null 2>&1; then
                    gdisk_log "LUKS opened via injected keyfile: ${cand}"
                fi
            fi

            # 2) Fall back to an interactive passphrase prompt (volumes with
            #    no embedded keyfile, or a key mismatch).
            if [ ! -b "/dev/mapper/${GDISK_LUKS_MAP}" ]; then
                TRIES=0
                while [ ${TRIES} -lt 3 ]; do
                    echo ""                                                       > /dev/console 2>/dev/null || true
                    echo "  Gdisk: unlock encrypted host ${cand} to boot ${GDISK_FILE}" > /dev/console 2>/dev/null || true
                    if cryptsetup open "${cand}" "${GDISK_LUKS_MAP}" < /dev/console > /dev/console 2>&1; then
                        gdisk_log "LUKS opened: ${cand} -> /dev/mapper/${GDISK_LUKS_MAP}"
                        break
                    fi
                    TRIES=$((TRIES + 1))
                done
            fi

            if [ -b "/dev/mapper/${GDISK_LUKS_MAP}" ]; then
                command -v udevadm >/dev/null 2>&1 && udevadm settle --timeout=10 2>/dev/null
                sleep 1
                case "${GDISK_DEV}" in
                    UUID=*|LABEL=*|PARTUUID=*)
                        HOST_BLKDEV=$(blkid -t "${GDISK_DEV}" -o device 2>/dev/null | head -1) ;;
                esac
                # Inner UUID unreadable from GRUB (gdisk.dev was a placeholder):
                # use the decrypted mapper directly.
                [ -z "${HOST_BLKDEV}" ] && [ -b "/dev/mapper/${GDISK_LUKS_MAP}" ] && \
                    HOST_BLKDEV="/dev/mapper/${GDISK_LUKS_MAP}"
                if [ -b "${HOST_BLKDEV}" ]; then
                    # dm-crypt extents are not physically contiguous on the
                    # parent disk, so FIEMAP mapping is invalid here; force loop.
                    GDISK_METHOD="loop"
                    break
                fi
                cryptsetup close "${GDISK_LUKS_MAP}" 2>/dev/null || true
            fi
        done
    else
        gdisk_log "ERROR: host is LUKS-encrypted but cryptsetup is missing from the initramfs"
    fi
fi

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

# --- udev rules: give the dm devices stable /dev/gdisk0pN symlinks ----------
_gdiskboot_udev_rules() {
    cat > "$1" << 'UDEVEOF'
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0",   SYMLINK+="gdisk0",   OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p1",  SYMLINK+="gdisk0p1",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p2",  SYMLINK+="gdisk0p2",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p3",  SYMLINK+="gdisk0p3",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p4",  SYMLINK+="gdisk0p4",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p5",  SYMLINK+="gdisk0p5",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p6",  SYMLINK+="gdisk0p6",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p7",  SYMLINK+="gdisk0p7",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p8",  SYMLINK+="gdisk0p8",  OPTIONS+="link_priority=100"
UDEVEOF
}

# =============================================================================
#  4. Per-generator installation
# =============================================================================

# ---- dracut ----------------------------------------------------------------
install_dracut() {
    msg "Installing dracut module..."
    local MODDIR=""
    for d in /usr/lib/dracut/modules.d /lib/dracut/modules.d; do
        [ -d "${d}" ] && MODDIR="${d}/99gdisk" && break
    done
    [ -n "${MODDIR}" ] || { err "dracut modules dir not found"; return 1; }
    mkdir -p /etc/dracut.conf.d
    rm -rf "${MODDIR}"; mkdir -p "${MODDIR}"

    cat > "${MODDIR}/module-setup.sh" << 'DSETUP'
#!/bin/bash
check() { require_binaries dmsetup blkid awk sed grep || return 1; return 255; }
depends() { echo dm; return 0; }
install() {
    inst_multiple dmsetup blkid awk sed grep dd stat losetup ln sleep cat mkdir mount umount modprobe
    for t in kpartx filefrag sfdisk partprobe blockdev cryptsetup; do
        command -v "$t" >/dev/null 2>&1 && inst_multiple "$t"
    done
    inst_hook initqueue/settled 90 "$moddir/gdisk-settled.sh"
    inst_simple "$moddir/gdisk-udev.rules" /etc/udev/rules.d/99-gdisk.rules
    dracut_need_initqueue
}
DSETUP
    chmod +x "${MODDIR}/module-setup.sh"
    _gdiskboot_generate_hook > "${MODDIR}/gdisk-settled.sh"; chmod +x "${MODDIR}/gdisk-settled.sh"
    _gdiskboot_udev_rules "${MODDIR}/gdisk-udev.rules"
    printf '%s\n' 'add_dracutmodules+=" gdisk "' 'force_drivers+=" dm-mod loop dm-crypt aes xts sha256 "' \
        > /etc/dracut.conf.d/gdisk.conf
    ok "Dracut module installed."
}

# ---- initramfs-tools -------------------------------------------------------
install_initramfs_tools() {
    msg "Installing initramfs-tools hooks..."
    mkdir -p /usr/share/initramfs-tools/hooks /etc/initramfs-tools/scripts/local-top
    cat > /usr/share/initramfs-tools/hooks/gdisk << 'ITHOOK'
#!/bin/sh
PREREQ="dmsetup"
prereqs() { echo "$PREREQ"; }
case $1 in prereqs) prereqs; exit 0 ;; esac
. /usr/share/initramfs-tools/hook-functions
for tool in dmsetup blkid awk sed grep dd stat losetup ln sleep cat mkdir mount umount modprobe; do
    for p in /bin /sbin /usr/bin /usr/sbin; do [ -f "$p/$tool" ] && copy_exec "$p/$tool" /sbin && break; done
done
for tool in kpartx filefrag sfdisk partprobe blockdev cryptsetup; do
    for p in /bin /sbin /usr/bin /usr/sbin; do [ -f "$p/$tool" ] && copy_exec "$p/$tool" /sbin && break; done
done
force_load dm-mod; force_load loop
force_load dm-crypt; force_load aes; force_load xts; force_load sha256
[ -f /etc/udev/rules.d/99-gdisk.rules ] && mkdir -p "$DESTDIR/etc/udev/rules.d" && cp /etc/udev/rules.d/99-gdisk.rules "$DESTDIR/etc/udev/rules.d/"
ITHOOK
    chmod +x /usr/share/initramfs-tools/hooks/gdisk
    _gdiskboot_generate_hook > /etc/initramfs-tools/scripts/local-top/gdisk
    chmod +x /etc/initramfs-tools/scripts/local-top/gdisk
    _gdiskboot_udev_rules /etc/udev/rules.d/99-gdisk.rules
    ok "initramfs-tools hooks installed."
}

# ---- mkinitcpio ------------------------------------------------------------
install_mkinitcpio() {
    msg "Installing mkinitcpio hooks..."
    mkdir -p /usr/lib/initcpio/install /usr/lib/initcpio/hooks
    cat > /usr/lib/initcpio/install/gdisk << 'MKINSTALL'
#!/bin/bash
build() {
    for b in dmsetup blkid awk sed grep dd stat losetup ln sleep cat mkdir mount umount modprobe; do add_binary "$b"; done
    for t in kpartx filefrag sfdisk partprobe blockdev cryptsetup; do command -v "$t" >/dev/null 2>&1 && add_binary "$t"; done
    add_module dm-mod; add_module loop; add_module dm-crypt; add_file /etc/udev/rules.d/99-gdisk.rules; add_runscript
}
help() { echo "Gdisk virtual disk boot support."; }
MKINSTALL
    chmod +x /usr/lib/initcpio/install/gdisk
    _gdiskboot_generate_hook > /usr/lib/initcpio/hooks/gdisk; chmod +x /usr/lib/initcpio/hooks/gdisk
    _gdiskboot_udev_rules /etc/udev/rules.d/99-gdisk.rules
    if [ -f /etc/mkinitcpio.conf ] && ! grep -q 'gdisk' /etc/mkinitcpio.conf; then
        warn "Add 'gdisk' to HOOKS in /etc/mkinitcpio.conf (after 'block', before 'filesystems'), then rerun mkinitcpio -P."
    fi
    ok "mkinitcpio hooks installed."
}

# =============================================================================
#  5. grub-probe wrapper (so grub run inside the guest copes with /dev/gdisk0)
# =============================================================================
install_grub_fixup() {
    msg "Installing GRUB probe wrapper..."
    local PROBE=""
    command -v grub-probe  >/dev/null 2>&1 && PROBE=$(command -v grub-probe)
    [ -z "$PROBE" ] && command -v grub2-probe >/dev/null 2>&1 && PROBE=$(command -v grub2-probe)
    [ -z "$PROBE" ] && { warn "grub-probe not found - skipping (not fatal)."; return 0; }
    if [ -f "${PROBE}-bk" ] && grep -q 'gdiskboot' "$PROBE" 2>/dev/null; then
        ok "GRUB probe wrapper already installed."; return 0
    fi
    [ -f "${PROBE}-bk" ] && mv "${PROBE}-bk" "$PROBE"
    cp -a "$PROBE" "${PROBE}-bk"
    cat > "$PROBE" << 'GPWRAP'
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
GPWRAP
    chmod +x "$PROBE"
    ok "GRUB probe wrapper installed."
}

# =============================================================================
#  6. Rebuild the initramfs
# =============================================================================
rebuild_initramfs() {
    msg "Rebuilding initramfs (${INITRAMFS_TOOL})..."
    case "${INITRAMFS_TOOL}" in
        dracut)
            dracut -f --no-hostonly || warn "dracut rebuild for running kernel reported errors"
            for k in /lib/modules/*/; do
                kn=$(basename "$k")
                [ "$kn" != "$(uname -r)" ] && [ -d "/lib/modules/${kn}/kernel" ] && \
                    dracut -f --no-hostonly --kver "$kn" || true
            done ;;
        initramfs-tools) update-initramfs -u -k all || die "update-initramfs failed" ;;
        mkinitcpio)      mkinitcpio -P || die "mkinitcpio failed" ;;
    esac
    ok "Initramfs rebuilt."
}

# =============================================================================
#  Execute
# =============================================================================
header "Installing gdiskboot hooks"

case "${INITRAMFS_TOOL}" in
    dracut)          install_dracut ;;
    initramfs-tools) install_initramfs_tools ;;
    mkinitcpio)      install_mkinitcpio ;;
esac

install_grub_fixup
rebuild_initramfs

header "Done"
echo "  ${BOLD}gdiskboot v${GDISKBOOT_VERSION} installed.${NC}"
echo
echo "  This system can now boot from a .gdisk file via Gdisk."
echo "  Gdisk passes on the kernel command line:"
echo "     gdisk.dev=UUID=<host>   host volume holding the .gdisk"
echo "     gdisk.file=<path>       path to the .gdisk inside that volume"
echo "     gdisk.root=<N>          root partition number inside the image"
echo "     gdisk.luks=1            host is LUKS-encrypted (self-unlock)"
echo
echo "  The early hook rebuilds the image into /dev/gdisk0 and /dev/gdisk0pN,"
echo "  then the normal initramfs mounts root from /dev/gdisk0p<gdisk.root>."
echo
if [ "${INITRAMFS_TOOL}" = "mkinitcpio" ]; then
    echo "  ${YEL}Reminder:${NC} ensure 'gdisk' is in HOOKS in /etc/mkinitcpio.conf"
    echo "           (after 'block', before 'filesystems') and rerun: mkinitcpio -P"
    echo
fi
