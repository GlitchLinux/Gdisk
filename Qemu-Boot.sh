#!/bin/bash
# Qemu-Boot.sh - Boot the physical disk containing this script in QEMU (BIOS or UEFI)
# Works from CLI, GUI double-click, or Thunar custom action.
# LF line endings only. exFAT-safe (no reliance on +x bit).

RAM_MB=4000
XRES=1920
YRES=1080

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
LOG="/tmp/qemu-boot.log"
QLOG="/tmp/qemu-boot-qemu.log"

# ══════════════════════════════════════════════════════════
# PHASE C: root worker - resolve disk, build args, detach QEMU
# ══════════════════════════════════════════════════════════
if [ "$1" = "--run" ]; then
    MODE="$2"
    SCRIPT_DIR="$3"

    if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
        echo " qemu-system-x86_64 not found"
        echo " sudo apt install qemu-system-x86"
        exit 1
    fi

    # Partition holding the script -> parent whole disk
    SRC_PART="$(df --output=source "$SCRIPT_DIR" | tail -n1)"
    PARENT_NAME="$(lsblk -no PKNAME "$SRC_PART" | head -n1)"
    if [ -n "$PARENT_NAME" ]; then
        DISK="/dev/$PARENT_NAME"
    else
        DISK="$SRC_PART"
    fi

    if [ ! -b "$DISK" ]; then
        echo " Not a block device: $DISK"
        exit 1
    fi

    # KVM if available, else TCG
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        ACCEL=(-accel kvm -cpu host)
    else
        ACCEL=(-accel tcg -cpu max)
    fi

    # Common args. AHCI/SATA instead of virtio so WinPE/Windows payloads see the disk.
    ARGS=(
        -name "Qemu-Boot-$MODE-$(basename "$DISK")"
        -m "$RAM_MB"
        "${ACCEL[@]}"
        -smp "$(nproc)"
        -drive "file=$DISK,format=raw,if=none,id=disk0,cache=none"
        -device ahci,id=ahci0
        -device ide-hd,drive=disk0,bus=ahci0.0,bootindex=1
        -vga none
        -device "VGA,edid=on,xres=$XRES,yres=$YRES"
        -netdev user,id=net0
        -device virtio-net-pci,netdev=net0
        -usb -device usb-tablet
        -rtc base=localtime
    )

    if [ "$MODE" = "UEFI" ]; then
        CODE=""
        VARS=""
        for pair in \
            "/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd" \
            "/usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd" \
            "/usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd" ; do
            c="${pair%%:*}"
            v="${pair##*:}"
            if [ -f "$c" ] && [ -f "$v" ]; then
                CODE="$c"
                VARS="$v"
                break
            fi
        done

        if [ -z "$CODE" ]; then
            echo " OVMF firmware not found"
            echo " sudo apt install ovmf"
            exit 1
        fi

        # Fresh writable NVRAM copy each boot
        VARS_COPY="/tmp/qemu-boot-OVMF_VARS.fd"
        cp -f "$VARS" "$VARS_COPY"

        ARGS=(
            -machine q35
            -drive "if=pflash,format=raw,readonly=on,file=$CODE"
            -drive "if=pflash,format=raw,file=$VARS_COPY"
            "${ARGS[@]}"
        )
    else
        ARGS=( -machine pc "${ARGS[@]}" )
    fi

    echo " Booting $DISK [$MODE]"
    echo " ${RAM_MB}MB RAM, $(nproc) CPUs"

    : > "$QLOG"
    setsid qemu-system-x86_64 "${ARGS[@]}" >>"$QLOG" 2>&1 < /dev/null &
    QPID=$!

    # Catch immediate failures instead of closing silently
    sleep 2
    if ! kill -0 "$QPID" 2>/dev/null; then
        echo
        echo " QEMU exited immediately:"
        tail -n 6 "$QLOG"
        exit 1
    fi
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

# Already on a tty without X/Wayland: run the TUI inline
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
        notify-send "Qemu-Boot" "No terminal emulator found. Install xterm."
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
        exec konsole --geometry 25x10 -p tabtitle="Qemu-Boot" \
            -e bash "$SCRIPT_PATH" --tui "$SCRIPT_DIR" ;;
    st)
        exec st -g 25x10 -t "Qemu-Boot" -e bash "$SCRIPT_PATH" --tui "$SCRIPT_DIR" ;;
esac
