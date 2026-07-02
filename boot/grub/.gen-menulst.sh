#!/bin/bash
# ====================================================================
#  gen-menulst.sh  -  Generate GRUB4DOS menu.lst for loadfm
# --------------------------------------------------------------------
#  GRUB4DOS menu.lst has no for-loops, so this scans the /Gdisk dir on
#  a mounted Gdisk partition and emits one block per .iso/.img/.wim.
#
#  NOW ALSO SEARCHES ONE DIRECTORY LEVEL DEEPER for files.
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
#    5. For each .wim  -> NTBOOT pe1= WIM boot block
#    6. Scan subdirs (/Gdisk/*/) for additional files
#    7. Append Back entry; copy to expected loadfm location
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
# ║ Gdisk v3 - GRUB4DOS menu.lst (auto-generated)     ║
# ║ Disk-backed map - boots .iso .img .wim >1GB       ║
# ║ Searches /Gdisk and /Gdisk/*/ (one level deep)    ║
# ╚═══════════════════════════════════════════════════╝
timeout 30
default 0
color black/cyan yellow/cyan
HEADER
shopt -s nullglob
# ---- ISO entries: CD emulation (0xff) ----
for f in "$GDISK_DIR"/*.iso "$GDISK_DIR"/*.ISO "$GDISK_DIR"/*/*.iso "$GDISK_DIR"/*/*.ISO; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    dir="$(basename "$(dirname "$f")")"
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
for f in "$GDISK_DIR"/*.img "$GDISK_DIR"/*.IMG "$GDISK_DIR"/*/*.img "$GDISK_DIR"/*/*.IMG; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    dir="$(basename "$(dirname "$f")")"
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
# ---- WIM entries: NTBOOT PE boot ----
for f in "$GDISK_DIR"/*.wim "$GDISK_DIR"/*.WIM "$GDISK_DIR"/*/*.wim "$GDISK_DIR"/*/*.WIM; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    dir="$(basename "$(dirname "$f")")"
    if [ "$dir" = "Gdisk" ]; then
        g4d="/Gdisk/$base"
    else
        g4d="/Gdisk/$dir/$base"
    fi
    {
        echo "title  [WIM]  $dir/$base"
        echo "find --set-root $g4d"
        echo "find --set-root /boot/grub/wimboot/initrd.img.xz"
        echo "/NTBOOT pe1=$g4d"
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
n_iso=$(find "$GDISK_DIR" -maxdepth 2 \( -iname "*.iso" \) -type f 2>/dev/null | wc -l)
n_img=$(find "$GDISK_DIR" -maxdepth 2 \( -iname "*.img" \) -type f 2>/dev/null | wc -l)
n_wim=$(find "$GDISK_DIR" -maxdepth 2 \( -iname "*.wim" \) -type f 2>/dev/null | wc -l)
echo "[+] Wrote $OUT_AGFM"
echo "[+] Wrote $OUT_ROOT"
echo "[+] Entries: $n_iso ISO, $n_img IMG, $n_wim WIM (scanned /Gdisk and /Gdisk/*/)"
