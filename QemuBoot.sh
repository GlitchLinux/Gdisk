#!/bin/bash
# qemu-boot.sh - Boot the physical disk containing this script in QEMU (BIOS or UEFI)
# Works from CLI, GUI double-click, or Thunar custom action.
# LF line endings only. exFAT-safe (no reliance on +x bit).

RAM_MB=5000
XRES=1920
YRES=1080

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
LOG="/tmp/qemu-boot.log"

# ══════════════════════════════════════════════════════════
# PHASE C: root worker - resolve disk, write launcher, detach
# ══════════════════════════════════════════════════════════
if [ "$1" = "--run" ]; then
    set -e
    MODE="$2"
    SCRIPT_DIR="$3"

    SRC_PART="$(df --output=source "$SCRIPT_DIR" | tail -n1)"
    PARENT_NAME="$(lsblk -no PKNAME "$SRC_PART" | head -n1)"
    if [ -z "$PARENT_NAME" ]; then
        DISK="$SRC_PART"
    else
        DISK="/dev/$PARENT_NAME"
    fi

    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        ACCEL="-enable-kvm -cpu host"
    else
        ACCEL="-cpu max"
    fi

    NCPU="$(nproc)"

    if [ "$MODE" = "BIOS" ]; then
        LAUNCHER="/tmp/.qemu-bios.sh"
        cat > "$LAUNCHER" <<EOF
#!/bin/bash
rm -f "\$(readlink -f "\${BASH_SOURCE[0]}")"
export DISPLAY="$DISPLAY"
export XAUTHORITY="$XAUTHORITY"
export WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
exec qemu-system-x86_64 \\
    -name "BIOS-Boot-$(basename "$DISK")" \\
    -m "$RAM_MB" \\
    $ACCEL \\
    -smp "$NCPU" \\
    -machine type=pc,accel=kvm:tcg \\
    -drive file="$DISK",format=raw,if=virtio,cache=none \\
    -boot order=c,menu=off \\
    -netdev user,id=net0 \\
    -device virtio-net-pci,netdev=net0 \\
    -usb -device usb-tablet \\
    -rtc base=localtime
EOF
    else
        OVMF_CODE=""
        OVMF_VARS_SRC=""
        for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd ; do
            [ -f "$c" ] && OVMF_CODE="$c" && break
        done
        for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd ; do
            [ -f "$v" ] && OVMF_VARS_SRC="$v" && break
        done
        if [ -z "$OVMF_CODE" ] || [ -z "$OVMF_VARS_SRC" ]; then
            echo "ERROR: OVMF firmware not found. Install with: apt install ovmf" >&2
            exit 1
        fi

        VARS_COPY="/tmp/qemu-ovmf-vars-$(basename "$DISK")-$$.fd"
        cp "$OVMF_VARS_SRC" "$VARS_COPY"

        LAUNCHER="/tmp/.qemu-uefi.sh"
        cat > "$LAUNCHER" <<EOF
#!/bin/bash
rm -f "\$(readlink -f "\${BASH_SOURCE[0]}")"
trap 'rm -f "$VARS_COPY"' EXIT
export DISPLAY="$DISPLAY"
export XAUTHORITY="$XAUTHORITY"
export WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
exec qemu-system-x86_64 \\
    -name "UEFI-Boot-$(basename "$DISK")" \\
    -m "$RAM_MB" \\
    $ACCEL \\
    -smp "$NCPU" \\
    -machine type=q35,accel=kvm:tcg \\
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \\
    -drive if=pflash,format=raw,file="$VARS_COPY" \\
    -drive file="$DISK",format=raw,if=virtio,cache=none \\
    -boot order=c,menu=off \\
    -netdev user,id=net0 \\
    -device virtio-net-pci,netdev=net0 \\
    -usb -device usb-tablet \\
    -rtc base=localtime
EOF
    fi

    chmod +x "$LAUNCHER" 2>/dev/null || true
    echo "Booting $DISK in QEMU [$MODE] with ${RAM_MB}MB RAM"
    setsid nohup bash "$LAUNCHER" >/dev/null 2>&1 < /dev/null &
    disown 2>/dev/null || true
    sleep 1
    exit 0
fi

# ══════════════════════════════════════════════════════════
# PHASE B: TUI - runs inside the small terminal, as the user
# ══════════════════════════════════════════════════════════
if [ "$1" = "--tui" ]; then
    SCRIPT_DIR="$2"
    while true; do
        clear
	echo
        echo " Qemu-Boot"
        echo
        echo " 1. BIOS"
        echo " 2. UEFI"
        echo
        printf "  ~> "
        read -r ans
        case "$ans" in
            1|b|B) MODE="BIOS" ; break ;;
            2|u|U) MODE="UEFI" ; break ;;
            q|Q)   exit 0 ;;
        esac
    done

    clear
    echo " Starting $MODE ..."
    echo

    if [ "$(id -u)" -eq 0 ]; then
        bash "$SCRIPT_PATH" --run "$MODE" "$SCRIPT_DIR"
    else
        sudo -E bash "$SCRIPT_PATH" --run "$MODE" "$SCRIPT_DIR"
    fi
    rc=$?

    if [ $rc -ne 0 ]; then
        echo
        echo " FAILED (exit $rc)"
        echo " Press enter to close."
        read -r _
    fi
    exit $rc
fi

# ══════════════════════════════════════════════════════════
# PHASE A: entry point - find a terminal and spawn the TUI
# ══════════════════════════════════════════════════════════
exec 2>>"$LOG"

# If we already have a tty and no X, just run the TUI inline
if [ -t 0 ] && [ -z "$DISPLAY$WAYLAND_DISPLAY" ]; then
    exec bash "$SCRIPT_PATH" --tui "$SCRIPT_DIR"
fi

TERM_CMD=""
for t in xfce4-terminal xterm lxterminal mate-terminal gnome-terminal konsole urxvt st ; do
    command -v "$t" >/dev/null 2>&1 && TERM_CMD="$t" && break
done

if [ -z "$TERM_CMD" ]; then
    if [ -t 0 ]; then
        exec bash "$SCRIPT_PATH" --tui "$SCRIPT_DIR"
    fi
    command -v notify-send >/dev/null 2>&1 && \
        notify-send "qemu-boot" "No terminal emulator found. Install xterm."
    echo "No terminal emulator found." >> "$LOG"
    exit 1
fi

case "$TERM_CMD" in
    xfce4-terminal)
        exec xfce4-terminal --geometry=25x10 --title="Qemu-Boot" --disable-server \
            -x bash "$SCRIPT_PATH" --tui "$SCRIPT_DIR" ;;
    xterm|urxvt)
        exec "$TERM_CMD" -geometry 25x10 -title "Qemu-Boot" \
            -e bash "$SCRIPT_PATH" --tui "$SCRIPT_DIR" ;;
    lxterminal)
        exec lxterminal --geometry=25x10 --title="Qemu-Boot" \
            -e bash "$SCRIPT_PATH" --tui "$SCRIPT_DIR" ;;
    mate-terminal|gnome-terminal)
        exec "$TERM_CMD" --geometry=25x10 --title="Qemu-Boot" \
            -- bash "$SCRIPT_PATH" --tui "$SCRIPT_DIR" ;;
    konsole)
        exec konsole --geometry 25x10 -p tabtitle="QEMU Boot" \
            -e bash "$SCRIPT_PATH" --tui "$SCRIPT_DIR" ;;
    st)
        exec st -g 25x10 -t "QEMU Boot" -e bash "$SCRIPT_PATH" --tui "$SCRIPT_DIR" ;;
esac
