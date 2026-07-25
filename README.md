## Gdisk -  Grub2  Device  Image  System  Kit

<img width="1280" height="360" alt="FullLogo_NoBuffer" src="https://github.com/user-attachments/assets/1080118d-18ac-4d28-9399-16b29014b5d7" />

---

Gdisk is a bootable multiboot USB manager built on **pure GRUB2 scripting** - on the
same path as Ventoy, GrubFM and Easy2Boot, but designed to be transparent, hackable
and centred around GRUB2. There are no opaque binaries: every menu, scan and boot
handler is a readable `.cfg` you can inspect and modify.

Custom GRUB modules extracted from GrubFM have been patched to allow raw `.iso` and
`.img` loopback booting in **UEFI** mode, and the boot chain installs a patched a1ive
`core.img` for hybrid **BIOS + UEFI** support from a single device.

---

## Features

- **Pure GRUB2 scripting** - no closed binaries; the whole menu system is editable text
- **Hybrid BIOS + UEFI** - one device boots on legacy CSM and modern UEFI machines
- **Raw ISO / IMG loopback boot** - direct UEFI booting of `.iso` and `.img` files
- **Dynamic pre-boot menus** - loopback-mounts an image, detects the OS, and offers the
  right boot paths automatically
- **Fast ISO scanner** - speed-optimised scan of every partition for bootable images
- **Partition & directory browser** - walks each partition and routes every file type to
  the correct boot handler
- **WIM / WinPE booting** - `.wim` and WinPE boot on both UEFI (grubfm `wimboot`) and BIOS,
  plus a native Windows Boot Manager loader
- **vDiskChain** - auto-scans all partitions for `.vtoy` disk images and chainloads them
- **Live-system entries** - direct boot menus for Glitch Linux, Bonsai and other live distros
- **Bundled loaders** - rEFInd, agFM (grubfm) and an iPXE network-boot framework under `EFI/`
- **Self-contained installers** - the Linux and Windows installers ship inside the device
  itself (`boot/Gdisk-Installer/`)

---

## Layout

```
Gdisk/
├── boot/
│   ├── grub/                 GRUB2 core: modules, theme, images, and all menu logic
│   │   ├── grub.cfg          primary entry - "Browse Partitions"
│   │   ├── i386-pc/          BIOS modules + patched core-patched.img / boot.img
│   │   ├── x86_64-efi/       UEFI modules
│   │   ├── gdisk-boot.cfg    dynamic loader for .iso .img .wim .vtoy
│   │   ├── gdisk-browse.cfg  directory browser
│   │   ├── iso-preboot.cfg   ISO pre-boot menu (loopback + OS detection)
│   │   ├── iso-scan.cfg      speed-optimised ISO scanner
│   │   ├── wim-preboot.cfg   WIM pre-boot menu
│   │   ├── winpe-native.cfg  native Windows Boot Manager / WinPE loader
│   │   ├── vdiskchain.cfg    .vtoy disk-image auto-scan and chainload
│   │   ├── glitch-live.cfg   Glitch Linux live boot
│   │   ├── agFM/  theme/  images/  wimboot/  vdiskchain/   supporting assets
│   │   └── font.pf2  grubenv  system.cfg
│   ├── Gdisk-Installer/      shipped installers: gdisk-v3-installer.sh, gdisk-v3-installer.exe,
│   └── Gdisk-Mkiso/          ISO-build scripts: gdisk-mkiso.sh
├── EFI/
│   ├── BOOT/BOOTX64.EFI      patched grubfm UEFI boot binary
│   ├── grubfm/               agFM loader (grubfmx64.efi)
│   ├── refind/               rEFInd boot manager
│   └── iPXE/                 iPXE network-boot binaries
├── Gdisk/                    live-system download helpers (.sh / .bat)
├── qemu-bios.sh             boot this device in QEMU (BIOS/SeaBIOS)
├── qemu-uefi.sh             boot this device in QEMU (UEFI/OVMF)
├── grub4dos.sh
├── autorun.inf
└── Gdisk.ico
```

---

## Installing Gdisk

There are three ways to install Gdisk v3.0 onto a target USB drive or disk.

### Method 1 - Linux Installer (gdisk-v3-installer.sh)

| Image | Format | Description |
|---|---|---|
| [gdisk-v3-installer.sh](https://github.com/GlitchLinux/Gdisk/releases/download/Gdisk-v3.0/gdisk-v3-installer.sh) | Linux Bash Script | Interactive CLI Installer |

A CLI installer that runs on any Linux system with GRUB2 tools available. Downloads the latest Gdisk files from GitHub and deploys them to the target device.

**Requirements:** Linux with `git`, `parted`, `mkfs.vfat`, `grub-bios-setup` (from `grub-pc-bin`)

Three operations are available:

- **Create** - Wipe a whole disk, create a new MBR partition table with a FAT32 partition (full disk or custom size), deploy all Gdisk files, and install the BIOS + UEFI boot chain.
- **Update** - Install or refresh Gdisk onto an existing partition. Existing user data is preserved, Gdisk boot files are added/overwritten.
- **Repair** - Reinstall the MBR core.img and/or UEFI BOOTX64.EFI on an existing Gdisk device without touching user data. Useful when the boot chain is broken but your ISOs and other files are fine.

### Method 2 - Windows Installer (gdisk-v3-installer.exe)

| Image | Format | Description |
|---|---|---|
| [gdisk-v3-installer.exe](https://github.com/GlitchLinux/Gdisk/releases/download/Gdisk-v3.0/gdisk-v3-installer.exe) | Portable Windows Executable | GUI Installer |

A portable GUI installer for Windows and WinPE. Everything is self-contained - `wget.exe`, `7z.exe` and a cross-compiled `grub-bios-setup.exe` are all embedded. No installation or external dependencies required.

The installer fetches the latest Gdisk build from GitHub, partitions and formats the target with `diskpart`, deploys the files, and installs the BIOS + UEFI boot chain. Works on physical drives and mounted virtual disks - anything `diskpart` can see.

Operations:

- **Create Gdisk device** - Format the target disk as MBR/FAT32 and deploy Gdisk
- **Update / Repair** - Reinstall the MBR boot chain and refresh boot files (`boot/` and `EFI/`), preserving user data

**Note:** Run as Administrator. In WinPE, the installer works out of the box since WinPE runs with full privileges.

### Method 3 - iPXE Network Boot (no local media needed)

| Image | Format | Description |
|---|---|---|
| [Gdisk-v3-Installer-iPXE.iso](https://github.com/GlitchLinux/Gdisk/releases/download/Gdisk-v3.0/gdisk-v3-installer-ipxe-hybrid.iso) | Bootable ISO | iPXE boots Debian minimal live, auto-launches `gdisk-v3.sh` |
| [Gdisk-v3-Installer-iPXE.img](https://github.com/GlitchLinux/Gdisk/releases/download/Gdisk-v3.0/gdisk-v3-installer-ipxe-efi.img) | EFI Partition Image | iPXE boots Debian minimal live, auto-launches `gdisk-v3.sh` |

For situations where you don't have a working Linux or Windows environment available, or you want to install Gdisk to the same disk you're booting from.

iPXE images boot a minimal Debian live system entirely into RAM via network boot. Once booted, the Gdisk installer runs automatically. Because the OS is running from RAM, the target disk is completely free - you can install Gdisk to the very disk you booted from.

**Requirements:** Wired internet connection (Ethernet). The iPXE boot image must be flashed to a USB stick or disk first using any raw image writer (dd, Rufus, Etcher, etc).

**iPXE install workflow:**

1. Download the iPXE ISO image
2. Launch in Virtual-Machine OR: 
3. Flash it to a USB stick using dd, Rufus, Etcher or similar:
   ```bash
   sudo dd if=gdisk-v3-installer-ipxe-hybrid.iso of=/dev/sdX bs=4M status=progress
   ```
4. Boot the target machine from the USB stick (BIOS or UEFI)
5. The system network-boots a minimal Debian live environment into RAM
6. The Gdisk installer (`gdisk-v3.sh`) starts automatically
7. Select your target disk - this can be the same USB stick you booted from, since the live system is running entirely from RAM
8. The installer downloads and deploys Gdisk to the target

---


## Booting

Boot the target device in either BIOS/CSM or UEFI mode. The primary menu opens on
**Browse Partitions**; from there you can walk partitions and directories, and Gdisk
routes each `.iso`, `.img`, `.wim` or `.vtoy` to the appropriate pre-boot handler.

You can also test a device without rebooting using the bundled QEMU scripts:

```bash
./qemu-bios.sh     # SeaBIOS
./qemu-uefi.sh     # OVMF (requires: apt install ovmf)
```

---

## Building an ISO

`boot/Gdisk-Mkiso/` contains scripts to build a bootable Gdisk `.iso` (including a
hybrid BIOS + UEFI El Torito image recognised by Rufus):

```bash
sudo bash boot/Gdisk-Mkiso/gdisk-mkiso.sh
```

```
╭────────────────────────────────────────────────╮
│    .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP │
│   dMP"      dMP VMP   amr   dMP" VP   dMP dMP  │
│  dMP MMP"  dMP dMP   dMP    VMMMb    dMMMM"    │   
│ dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP"AMF    │ 
│ VMMMP"   dMMMMP"   dMP    VMMMP"   dMP dMP     │
╭────────────────────────────────────────────────╮
│  Grub2   Device   Image   System   Kit  -  v3  │
╰────────────────────────────────────────────────╯
```

---

## Related

- **grub2-patch** - the patched GrubFM-derived modules that enable raw UEFI
  loopback booting: https://github.com/GlitchLinux/grub2-patch

---

Source: https://github.com/GlitchLinux  ·  GPLv3
