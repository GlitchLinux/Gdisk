# ╔════════════════════════════════════════════════╗
# ║  Gdisk - .gdisk Virtual Disk Pre-Boot Menu     ║
# ║  Variables expected (exported by caller):      ║
# ║    gdisk_path  = "/Gdisk/mylinux.gdisk"        ║
# ╚════════════════════════════════════════════════╝

if [ ! -x /usr/sbin/kpartx ]; then
  sudo apt update && sudo apt install kpartx -y
fi

insmod regexp
insmod loopback
insmod probe
insmod part_gpt
insmod part_msdos
insmod ext2
insmod xfs
insmod btrfs
insmod fat
insmod ntfs
insmod linux

set timeout=3
set default=0
set color_normal=white/black
set color_highlight=cyan/black

regexp --set=gdisk_name '.*/([^/]+)$' "${gdisk_file}"
if [ -z "${gdisk_name}" ]; then
    set gdisk_name="${gdisk_path}"
fi

probe --set=host_uuid -u "(${gdisk_dev})"

if [ -n "${host_uuid}" ]; then
    set host_dev_param="gdisk.dev=UUID=${host_uuid}"
else
    set host_dev_param="gdisk.dev=/dev/sda1"
fi

loopback gdloop "${gdisk_file}"

set gdisk_found_kernel=0

for pnum in 1 2 3 4; do
    for pscheme in gpt msdos; do
        set trydev="gdloop,${pscheme}${pnum}"

        if [ -d "(${trydev})/" ]; then

            # ── /boot/vmlinuz-* (standard layout) ────────
            for kfile in (${trydev})/boot/vmlinuz-*; do
                if [ -f "${kfile}" ]; then
                    regexp --set=kver '/boot/vmlinuz-(.+)$' "${kfile}"

                    set found_initrd=""
                    if [ -f "(${trydev})/boot/initrd.img-${kver}" ]; then
                        set found_initrd="/boot/initrd.img-${kver}"
                    elif [ -f "(${trydev})/boot/initramfs-${kver}.img" ]; then
                        set found_initrd="/boot/initramfs-${kver}.img"
                    elif [ -f "(${trydev})/boot/initrd-${kver}.img" ]; then
                        set found_initrd="/boot/initrd-${kver}.img"
                    fi

                    if [ -n "${found_initrd}" ]; then
                        set gdisk_found_kernel=1

                        menuentry "Linux ${kver}  [p${pnum}]  -  ${gdisk_name}" \
                                  "${trydev}" "/boot/vmlinuz-${kver}" "${found_initrd}" \
                                  "${host_dev_param}" "${gdisk_path}" "${pnum}" {
                            set gfxpayload=keep
                            linux  "(${2})${3}" root=/dev/gdisk0p${7} ro ${5} gdisk.file=${6} gdisk.root=${7} quiet
                            initrd "(${2})${4}"
                        }
                    fi
                fi
            done

            # ── /vmlinuz-* (separate /boot partition) ────
            for kfile in (${trydev})/vmlinuz-*; do
                if [ -f "${kfile}" ]; then
                    regexp --set=kver '/vmlinuz-(.+)$' "${kfile}"

                    set found_initrd=""
                    if [ -f "(${trydev})/initrd.img-${kver}" ]; then
                        set found_initrd="/initrd.img-${kver}"
                    elif [ -f "(${trydev})/initramfs-${kver}.img" ]; then
                        set found_initrd="/initramfs-${kver}.img"
                    elif [ -f "(${trydev})/initrd-${kver}.img" ]; then
                        set found_initrd="/initrd-${kver}.img"
                    fi

                    if [ -n "${found_initrd}" ]; then
                        set gdisk_found_kernel=1

                        menuentry "Linux ${kver}  [boot:p${pnum}]  -  ${gdisk_name}" \
                                  "${trydev}" "/vmlinuz-${kver}" "${found_initrd}" \
                                  "${host_dev_param}" "${gdisk_path}" "${pnum}" {
                            set gfxpayload=keep
                            linux  "(${2})${3}" root=/dev/gdisk0p${7} ro ${5} gdisk.file=${6} gdisk.root=${7} quiet
                            initrd "(${2})${4}"
                        }
                    fi
                fi
            done

            # ── /boot/vmlinuz or /vmlinuz (unversioned) ──
            for kpath in /boot/vmlinuz /vmlinuz; do
                if [ -f "(${trydev})${kpath}" ]; then
                    set found_initrd=""
                    if [ -f "(${trydev})/boot/initrd.img" ]; then
                        set found_initrd="/boot/initrd.img"
                    elif [ -f "(${trydev})/boot/initramfs.img" ]; then
                        set found_initrd="/boot/initramfs.img"
                    elif [ -f "(${trydev})/initrd.img" ]; then
                        set found_initrd="/initrd.img"
                    elif [ -f "(${trydev})/initramfs.img" ]; then
                        set found_initrd="/initramfs.img"
                    fi

                    if [ -n "${found_initrd}" ]; then
                        set gdisk_found_kernel=1

                        menuentry "Linux (generic)  [p${pnum}]  -  ${gdisk_name}" \
                                  "${trydev}" "${kpath}" "${found_initrd}" \
                                  "${host_dev_param}" "${gdisk_path}" "${pnum}" {
                            set gfxpayload=keep
                            linux  "(${2})${3}" root=/dev/gdisk0p${7} ro ${5} gdisk.file=${6} gdisk.root=${7} quiet
                            initrd "(${2})${4}"
                        }
                    fi
                fi
            done
        fi
    done
done

if [ "${gdisk_found_kernel}" = "0" ]; then
    set timeout=-1

    if [ "${grub_platform}" = "efi" ]; then
        menuentry "Boot ${gdisk_name} (UEFI disk map)" "${gdisk_file}" {
            loopback -d gdloop
            insmod map
            map -f "${2}"
        }
    fi

    menuentry "No kernels found inside ${gdisk_name}" {
        echo ""
        echo "  No vmlinuz + initrd pair detected."
        echo "  Scanned: /boot/vmlinuz-* and /vmlinuz-*"
        echo "  on partitions 1-4 (gpt and msdos)"
        echo ""
        echo "  Press any key..."
        read
    }
fi

menuentry "[<-] Back" {
    loopback -d gdloop
    configfile /boot/grub/gdisk-scan.cfg
}
