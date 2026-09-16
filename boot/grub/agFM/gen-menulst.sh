#!/bin/bash
# ====================================================================
#  gen-menulst.sh  -  Generate GRUB4DOS menu.lst for loadfm
# --------------------------------------------------------------------
#  GRUB4DOS menu.lst has no for-loops, so this scans the /Gdisk dir on
#  a mounted Gdisk partition and emits one disk-backed map block per
#  .iso/.img. Disk-backed map (no --mem) has NO 1GB size limit.
#
#  Run it pointed at the MOUNTED Gdisk partition, e.g.:
#     ./gen-menulst.sh /media/x/GDISK-V2
#  It writes <mount>/boot/grub/agFM/menu.lst (and a copy at root).
#
#  EXECUTION FLOW:
#    1. Resolve mount point + /Gdisk dir
#    2. Write menu.lst header (timeout/default/colors)
#    3. For each .iso  -> map (0xff) CD-emulation block
#    4. For each .img  -> map (hd32) HDD-emulation block
#    5. Append Back entry; copy to expected loadfm location
# ====================================================================

set -uo pipefail

MNT="${1:-}"
[ -n "$MNT" ] || { echo "usage: $0 /path/to/mounted/gdisk/partition"; exit 1; }
[ -d "$MNT" ] || { echo "not a directory: $MNT"; exit 1; }

GDISK_DIR="$MNT/Gdisk"
[ -d "$GDISK_DIR" ] || { echo "no /Gdisk dir under $MNT"; exit 1; }

# loadfm/grub4dos looks for menu.lst; write to both common spots
OUT_AGFM="$MNT/boot/grub/agFM/menu.lst"
OUT_ROOT="$MNT/menu.lst"
mkdir -p "$(dirname "$OUT_AGFM")"

TMP="$(mktemp)"

# ---- header ----
cat > "$TMP" <<'HEADER'
# ╔═════════════════════════════════════════════╗
# ║ Gdisk v2 - GRUB4DOS menu.lst (auto-generated)║
# ║ Disk-backed map - boots .iso .img >1GB      ║
# ╚═════════════════════════════════════════════╝
timeout 30
default 0
color black/cyan yellow/cyan

HEADER

shopt -s nullglob

# ---- ISO entries: CD emulation (0xff) ----
for f in "$GDISK_DIR"/*.iso "$GDISK_DIR"/*.ISO; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    # grub4dos path = absolute path on the partition, leading slash
    g4d="/Gdisk/$base"
    {
        echo "title  [ISO]  $base"
        echo "find --set-root $g4d"
        echo "map $g4d (0xff)"
        echo "map --hook"
        echo "chainloader (0xff)"
        echo "boot"
        echo
    } >> "$TMP"
done

# ---- IMG entries: HDD emulation (hd32) ----
for f in "$GDISK_DIR"/*.img "$GDISK_DIR"/*.IMG; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    g4d="/Gdisk/$base"
    {
        echo "title  [IMG]  $base"
        echo "find --set-root $g4d"
        echo "map $g4d (hd32)"
        echo "map --hook"
        echo "chainloader (hd32)+1"
        echo "rootnoverify (hd32)"
        echo "boot"
        echo
    } >> "$TMP"
done

# ---- back entry ----
cat >> "$TMP" <<'FOOTER'
title  [<-] Reboot / Back
reboot
FOOTER

cp -f "$TMP" "$OUT_AGFM"
cp -f "$TMP" "$OUT_ROOT"
rm -f "$TMP"

n_iso=$(ls "$GDISK_DIR"/*.iso "$GDISK_DIR"/*.ISO 2>/dev/null | wc -l)
n_img=$(ls "$GDISK_DIR"/*.img "$GDISK_DIR"/*.IMG 2>/dev/null | wc -l)
echo "[+] Wrote $OUT_AGFM"
echo "[+] Wrote $OUT_ROOT"
echo "[+] Entries: $n_iso ISO, $n_img IMG"