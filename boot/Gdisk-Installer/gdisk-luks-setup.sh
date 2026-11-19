#!/bin/bash
# ╔════════════════════════════════════════════════════════════════════╗
# ║ encrypted-partition-setup.sh                                       ║
# ║ Wipe a pre-existing partition, LUKS-encrypt it, and register its   ║
# ║ UUID in the gdisk-crypto.cfg of the Gdisk device this is run from  ║
# ╚════════════════════════════════════════════════════════════════════╝
#
# GRUB in Gdisk has NO argon2 module, so this uses LUKS1 (PBKDF2), which
# GRUB's cryptomount can always open. Do not switch to default LUKS2.
#
# Run as root from the Gdisk device, e.g.:
#   sudo /boot/Gdisk-Installer/gdisk-luks-setup.sh

set -eu

rm -f ../grub/gdisk-crypto.cfg
touch ../grub/gdisk-crypto.cfg

MAPNAME="gdisk_luks_setup"
FSLABEL="Gdisk-Luks"
RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYA=$'\e[36m'; RST=$'\e[0m'
info(){ echo "${CYA}==>${RST} $*"; }
ok(){   echo "${GRN}OK:${RST} $*"; }
warn(){ echo "${YEL}!!${RST} $*"; }
die(){  echo "${RED}ERROR:${RST} $*" >&2; exit 1; }
cleanup(){ cryptsetup close "$MAPNAME" 2>/dev/null || true; }
trap cleanup EXIT

# --- preconditions ---------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)."
command -v cryptsetup >/dev/null || die "cryptsetup not found."
command -v lsblk      >/dev/null || die "lsblk not found."

# --- locate this script and its Gdisk device's gdisk-crypto.cfg ------------
SELF="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SELF")"
CRYPTO_CFG="$(readlink -f "$SCRIPT_DIR/../grub/gdisk-crypto.cfg" 2>/dev/null || true)"
[ -n "$CRYPTO_CFG" ] && [ -f "$CRYPTO_CFG" ] || \
    die "could not find ../grub/gdisk-crypto.cfg next to this script ($SCRIPT_DIR)."
info "Gdisk crypto config: $CRYPTO_CFG"

# source partition that holds this script (never encrypt that one)
if command -v findmnt >/dev/null; then
    SELF_PART="$(findmnt -n -o SOURCE --target "$SCRIPT_DIR" 2>/dev/null || true)"
else
    SELF_PART="$(df --output=source "$SCRIPT_DIR" 2>/dev/null | tail -1 || true)"
fi
SELF_PART="$(readlink -f "$SELF_PART" 2>/dev/null || echo "$SELF_PART")"
info "This Gdisk device lives on: ${SELF_PART:-unknown}"

# --- choose target partition -----------------------------------------------
echo
info "Block devices on this system:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
echo
warn "The partition you pick will be COMPLETELY WIPED."
read -rp "Partition to encrypt (e.g. /dev/sdb2): " TARGET
[ -n "$TARGET" ] || die "no partition given."
case "$TARGET" in /dev/*) ;; *) TARGET="/dev/$TARGET" ;; esac
TARGET="$(readlink -f "$TARGET" 2>/dev/null || echo "$TARGET")"

# --- validate --------------------------------------------------------------
[ -b "$TARGET" ] || die "$TARGET is not a block device."
TTYPE="$(lsblk -ndo TYPE "$TARGET" 2>/dev/null || true)"
[ "$TTYPE" = "part" ] || die "$TARGET is type '${TTYPE:-?}', not a partition. Create the partition first."
[ "$TARGET" != "$SELF_PART" ] || die "that is the partition this Gdisk device runs from. Refusing."
MNT="$(lsblk -no MOUNTPOINT "$TARGET" 2>/dev/null | grep -v '^$' || true)"
[ -z "$MNT" ] || die "$TARGET is mounted at: $MNT . Unmount it first."

TSIZE="$(lsblk -ndo SIZE "$TARGET")"
echo
warn "About to ERASE and encrypt ${RED}$TARGET${RST} ($TSIZE)."
read -rp "Type the full device path again to confirm: " CONFIRM
[ "$CONFIRM" = "$TARGET" ] || die "confirmation did not match. Aborting."

# --- passphrase (entered once) ---------------------------------------------
echo
read -rsp "New LUKS passphrase: " PP;  echo
read -rsp "Repeat passphrase:   " PP2; echo
[ -n "$PP" ] || die "empty passphrase."
[ "$PP" = "$PP2" ] || die "passphrases do not match."
unset PP2

# --- LUKS1 format + open ----------------------------------------------------
info "Formatting $TARGET as LUKS1 (aes-xts-plain64 / sha256, PBKDF2)..."
printf '%s' "$PP" | cryptsetup luksFormat --type luks1 \
    --cipher aes-xts-plain64 --hash sha256 --key-size 512 \
    --batch-mode "$TARGET" -
ok "LUKS1 header written."

info "Opening the volume..."
printf '%s' "$PP" | cryptsetup open "$TARGET" "$MAPNAME" -
ok "Opened as /dev/mapper/$MAPNAME"

# --- optional filesystem inside --------------------------------------------
echo
echo "Filesystem to create inside the encrypted volume:"
echo "  1) FAT32   (default - best GRUB/Gdisk support)"
echo "  2) ext4"
echo "  3) exfat"
echo "  4) ntfs"
echo "  5) none    (leave raw - not browsable until you format it)"
read -rp "Choice [1]: " FSC; FSC="${FSC:-1}"
case "$FSC" in
    1) mkfs.vfat -F32 -n "$FSLABEL" "/dev/mapper/$MAPNAME" >/dev/null && ok "FAT32 created." ;;
    2) mkfs.ext4 -q -L "$FSLABEL" "/dev/mapper/$MAPNAME"   && ok "ext4 created." ;;
    3) mkfs.exfat -n "$FSLABEL" "/dev/mapper/$MAPNAME"     >/dev/null && ok "exfat created." ;;
    4) mkfs.ntfs -f -L "$FSLABEL" "/dev/mapper/$MAPNAME"   >/dev/null && ok "ntfs created." ;;
    5) warn "No filesystem created." ;;
    *) warn "Unknown choice - no filesystem created." ;;
esac

cryptsetup close "$MAPNAME"
unset PP

# --- register UUID in gdisk-crypto.cfg -------------------------------------
# GRUB on this build matches the dash-STRIPPED LUKS UUID, so store that form.
UUID_ND="$(cryptsetup luksUUID "$TARGET" | tr -d -)"
[ -n "$UUID_ND" ] || die "could not read LUKS UUID back from $TARGET."
info "LUKS UUID (dash-stripped): $UUID_ND"

# regenerate the config (placeholder filled after the heredoc)
cat > "$CRYPTO_CFG" <<'GRUBCFG'
# ╔══════════════════════════════════════════════════╗
# ║ gdisk-crypto.cfg - unlock a LUKS volume by UUID, ║
# ║ then list its files in the native Gdisk browser  ║
# ╚══════════════════════════════════════════════════╝
# UUID below is written by gdisk-luks-setup.sh (dashes stripped,
# which is what this GRUB build matches). Container is LUKS1 (PBKDF2) -
# GRUB here has no argon2 module.

insmod part_msdos
insmod part_gpt
insmod cryptodisk
insmod luks
insmod gcry_rijndael
insmod gcry_sha256
insmod gcry_sha512
insmod pbkdf2
insmod afsplitter
insmod fat
insmod iso9660
insmod loopback
insmod regexp
insmod probe
insmod png

set timeout=15
set default=0
set theme=/boot/grub/theme/theme-luks.cfg
set color_normal=white/black
set color_highlight=white/black

# >>> managed by gdisk-luks-setup.sh - do not edit this line <<<
set crypto_uuid="__UUID_ND__"
# <<< end managed >>>

echo " "
echo " "
echo " "
echo " "
echo " "

if cryptomount -u "${crypto_uuid}"; then
    set gdisk_browse_dev="crypto0"
    set gdisk_browse_path=""
    export gdisk_browse_dev
    export gdisk_browse_path
    configfile /boot/grub/gdisk-browse.cfg
else
    echo ""
    echo "  Unlock failed - wrong passphrase, or no LUKS volume with that UUID."
    echo "  Press any key to return to the Gdisk menu..."
    read _dummy
    configfile /boot/grub/gdisk-boot.cfg
fi
GRUBCFG

sed -i "s/__UUID_ND__/$UUID_ND/" "$CRYPTO_CFG"
sync

echo
ok "Done. $TARGET is encrypted (label: $FSLABEL) and registered."
echo "   In Gdisk: 'Gdisk Decrypt LUKS' unlocks and lists it; afterwards it also"
echo "   appears under 'Gdisk Browse Partitions' as a (crypto0) *LUKS* entry."
