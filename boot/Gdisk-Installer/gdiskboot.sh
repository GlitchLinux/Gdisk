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

if [ ! -x /usr/sbin/kpartx ]; then
  sudo apt update && sudo apt install kpartx -y
fi

set -e

GDISKBOOT_VERSION="0.3"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[gdiskboot]${NC} $*"; }
ok()    { echo -e "${GREEN}[gdiskboot]${NC} $*"; }
warn()  { echo -e "${YELLOW}[gdiskboot]${NC} $*"; }
err()   { echo -e "${RED}[gdiskboot]${NC} $*" >&2; }

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
echo "  ╔═════════════════════════════════════╗"
echo "  ║  gdiskboot v${GDISKBOOT_VERSION}                     ║"
echo "  ║  Gdisk Virtual Disk Boot Installer  ║"
echo "  ║  github.com/GlitchLinux/Gdisk       ║"
echo "  ╚═════════════════════════════════════╝"
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
