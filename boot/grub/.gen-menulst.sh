#!/bin/bash
# ====================================================================
#  gen-menulst.sh  -  Generate GRUB4DOS menu.lst for loadfm
# --------------------------------------------------------------------
#  GRUB4DOS menu.lst has no for-loops, so this scans the /Gdisk dir on
#  a mounted Gdisk partition and emits one disk-backed map block per
#  .iso/.img. Disk-backed map (no --mem) has NO 1GB size limit.
#
#  NOW ALSO SEARCHES ONE DIRECTORY LEVEL DEEPER for .iso/.img files.
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
#    5. Scan subdirs (/Gdisk/*/) for additional .iso/.img files
#    6. Append Back entry; copy to expected loadfm location
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
# ╔═══════════════════════════════════════════════════╗
# ║ Gdisk v2 - GRUB4DOS menu.lst (auto-generated)     ║
# ║ Disk-backed map - boots .iso .img >1GB            ║
# ║ Searches /Gdisk and /Gdisk/*/ (one level deep)    ║
# ╚═══════════════════════════════════════════════════╝
timeout 30
default 0
color black/cyan yellow/cyan
HEADER
shopt -s nullglob
# ---- ISO entries: CD emulation (0xff) ----
# Search both $GDISK_DIR/*.iso and $GDISK_DIR/*/*.iso (one level deeper)
for f in "$GDISK_DIR"/*.iso "$GDISK_DIR"/*.ISO "$GDISK_DIR"/*/*.iso "$GDISK_DIR"/*/*.ISO; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    dir="$(basename "$(dirname "$f")")"
    
    # Build grub4dos path: if in subdir, include it; else just filename
    if [ "$dir" = "Gdisk" ]; then
        g4d="/Gdisk/$base"
    else
        g4d="/Gdisk/$dir/$base"
    fi
    
    {
        echo "title  [ISO]  $dir/$base"
        echo "find --set-root $g4d"
        echo "map $g4d (0xff)"
        echo "map --hook"
        echo "chainloader (0xff)"
        echo "boot"
        echo
    } >> "$TMP"
done
# ---- IMG entries: HDD emulation (hd32) ----
# Search both $GDISK_DIR/*.img and $GDISK_DIR/*/*.img (one level deeper)
for f in "$GDISK_DIR"/*.img "$GDISK_DIR"/*.IMG "$GDISK_DIR"/*/*.img "$GDISK_DIR"/*/*.IMG; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    dir="$(basename "$(dirname "$f")")"
    
    # Build grub4dos path: if in subdir, include it; else just filename
    if [ "$dir" = "Gdisk" ]; then
        g4d="/Gdisk/$base"
    else
        g4d="/Gdisk/$dir/$base"
    fi
    
    {
        echo "title  [IMG]  $dir/$base"
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
# ---- summary ----
n_iso=$(find "$GDISK_DIR" -maxdepth 2 \( -iname "*.iso" \) -type f | wc -l)
n_img=$(find "$GDISK_DIR" -maxdepth 2 \( -iname "*.img" \) -type f | wc -l)
echo "[+] Wrote $OUT_AGFM"
echo "[+] Wrote $OUT_ROOT"
echo "[+] Entries: $n_iso ISO, $n_img IMG (scanned /Gdisk and /Gdisk/*/)"
