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

> **Latest release: [v3.2](https://github.com/GlitchLinux/Gdisk/releases/tag/Gdisk-v3.2)** - the whole utility has been updated and optimized, and a new portable **Linux GUI installer** is available.

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
- **VHD / VHDX booting** - native NT6+ boot of `.vhd` and `.vhdx` via `ntloader` on both
  UEFI and BIOS, plus raw disk-mapping fallbacks (`map`, grub4dos, memdisk) for fixed VHDs.
  See "VHD / VHDX boot" below for the NTFS requirement.
- **vDiskChain** - auto-scans all partitions for `.vtoy` disk images and chainloads them
- **Live-system entries** - direct boot menus for Glitch Linux, Bonsai and other live distros
- **Bundled loaders** - rEFInd, agFM (grubfm) and an iPXE network-boot framework under `EFI/`
- **Flexible installers** - portable Linux GUI installer, Linux CLI installer, Windows
  installer and iPXE network install, with selectable disk layouts
  (FAT32, FAT32 + NTFS, FAT32 + exFAT)
- **Self-contained installers** - the CLI and Windows installers also ship inside the device
  itself (`boot/Gdisk-Installer/`)

---

## Layout

```
Gdisk/
├── boot/
│   ├── grub/                           GRUB2 core: modules, theme, images, and all menu logic
│   │   ├── grub.cfg                    entry point - hands off to gdisk.cfg
│   │   ├── gdisk.cfg                   main menu (v3.2)
│   │   ├── gdisk-partitions.cfg        "Browse Partitions" partition list
│   │   ├── gdisk-browse.cfg            directory browser
│   │   ├── gdisk-boot.cfg              dynamic loader for .iso .img .wim .vhd .vhdx .vtoy
│   │   ├── iso-preboot.cfg             ISO pre-boot menu (loopback + OS detection)
│   │   ├── img-preboot.cfg             IMG pre-boot menu (loopback + analysis)
│   │   ├── wim-preboot.cfg             WIM pre-boot menu
│   │   ├── vhd-preboot.cfg             VHD/VHDX pre-boot menu (ntloader, ntboot, raw maps)
│   │   ├── iso-scan.cfg                speed-optimised ISO scanner
│   │   ├── vhd-scan.cfg                .vhd/.vhdx auto-scan across all partitions
│   │   ├── wimdiskchain.cfg            dynamic WIM boot scanner (all partitions)
│   │   ├── wimboot-scan.cfg            wimboot payload with dynamic .wim discovery
│   │   ├── winpe-native.cfg            native Windows Boot Manager / WinPE loader
│   │   ├── winpe-iso.cfg               WinPE ISO boot menu
│   │   ├── vdiskchain.cfg              .vtoy disk-image auto-scan and chainload
│   │   ├── glitch-live.cfg             Glitch Linux live boot
│   │   ├── linux-live.cfg              Linux live system boot entries
│   │   ├── grub-ipxe.cfg               Glitch iPXE multi-net-boot (UEFI / BIOS)
│   │   ├── system.cfg                  System menu
│   │   ├── release.cfg                 disclaimer / banner screen
│   │   ├── iso-boot.cfg  iso-menu.cfg  legacy v2.0 ISO menus (not linked from main menu)
│   │   ├── boot-local-efi.cfg          boot local EFI loader from 1st drive (unlinked helper)
│   │   ├── i386-pc/                    BIOS modules + patched core-patched.img / boot.img
│   │   ├── x86_64-efi/                 UEFI modules
│   │   ├── ntloader/                   ntloader v3.0.7 + initrd.cpio (NT6+ VHD/VHDX/WIM)
│   │   ├── agFM/  theme/  images/  fonts/  locale/  wimboot/  vdiskchain/   supporting assets
│   │   └── efi.img  font.pf2  grubenv
│   ├── Gdisk-Installer/                CLI, Windows and GUI installers (+ payload helpers)
│   ├── Gdisk-Mkiso/                    ISO-build scripts (gdisk-mkiso.sh + custom variants)
│   └── Gdisk-Scripts/                  QEMU launchers, grub4dos generator, WIM converters, download helpers
├── EFI/
│   ├── BOOT/BOOTX64.EFI                patched grubfm UEFI boot binary
│   ├── grubfm/                         agFM loader (grubfmx64.efi)
│   ├── refind/                         rEFInd boot manager
│   └── iPXE/                           iPXE network-boot binary (Glitch-iPXE.efi)
├── Gdisk/                              drop folder for bootable files (.iso .img .vtoy .wim .vhd .vhdx .ima)
├── Qemu-Boot.sh                        boot this device in QEMU (BIOS or UEFI)
├── autorun.inf
├── Gdisk.ico
└── README.md
```

---

<img width="902" height="755" alt="gdisk-gui-installer" src="https://github.com/user-attachments/assets/9c380aac-ae52-4770-b055-aa717cec7c72" />


## Installing Gdisk

There are four ways to install Gdisk onto a target USB drive or disk. The Linux GUI installer is the recommended starting point.

### Method 1 - Linux GUI Installer (gdisk-v3.2-gui-linux)

| Image | Format | Description |
|---|---|---|
| [gdisk-v3.2-gui-linux](https://github.com/GlitchLinux/Gdisk/releases/download/Gdisk-v3.2/gdisk-v3.2-gui-linux) | Portable Linux Binary | GUI Installer |

A graphical installer for Linux. It is a single portable binary, so there is nothing to install and no dependencies to set up first. Make it executable and launch it with `sudo`:

```bash
chmod +x gdisk-v3.2-gui-linux
sudo ./gdisk-v3.2-gui-linux
```

Root is required because the installer partitions, formats and writes boot code to the target disk. It drives the same **Create**, **Update** and **Repair** operations and the same disk layouts as the CLI installer below.

### Method 2 - Linux CLI Installer (gdisk-v3-installer.sh)

| Image | Format | Description |
|---|---|---|
| [gdisk-v3-installer.sh](https://github.com/GlitchLinux/Gdisk/releases/download/Gdisk-v3.2/gdisk-v3-installer.sh) | Linux Bash Script | Interactive CLI Installer |

An interactive CLI installer that runs on any Linux system with GRUB2 tools available. Downloads the latest Gdisk files from GitHub and deploys them to the target device. Must be run as root:

```bash
chmod +x gdisk-v3-installer.sh
sudo ./gdisk-v3-installer.sh
```

**Requirements:** Linux with `git`, `parted`, `mkfs.vfat`, `rsync`, `grub-bios-setup` (from `grub-pc-bin`). Missing tools are detected and the installer offers to install them with your package manager (apt, dnf, yum, pacman or zypper). The NTFS and exFAT layouts additionally need `mkfs.ntfs` (`ntfs-3g`) or `mkfs.exfat`.

Three operations are available:

- **Create** - Wipe a whole disk, create a new MBR partition table with the layout of your choice (see below), deploy all Gdisk files, and install the BIOS + UEFI boot chain.
- **Update** - Install or refresh Gdisk onto an existing partition. Existing user data is preserved, Gdisk boot files are added/overwritten.
- **Repair** - Reinstall the MBR core.img and/or UEFI BOOTX64.EFI on an existing Gdisk device without touching user data. Useful when the boot chain is broken but your ISOs and other files are fine.

**Disk layouts for Create:**

| Layout | Partitions |
|---|---|
| Pure FAT32 | Single FAT32 partition across the whole disk |
| FAT32 + NTFS | 32 MB `Gdisk-EFI` FAT32 partition + `Gdisk-Ntfs` data partition (custom size or rest of disk) |
| FAT32 + exFAT | 32 MB `Gdisk-EFI` FAT32 partition + `Gdisk-exFAT` data partition (custom size or rest of disk) |

In the two hybrid layouts the small FAT32 partition holds the GRUB modules and `BOOTX64.EFI`, while the data partition holds your boot images (ISO / IMG / WIM / VHD). Use **FAT32 + NTFS** if you want native VHD / VHDX boot, which requires NTFS. Both hybrid layouts also avoid the 4 GiB single-file limit of FAT32.

### Method 3 - Windows Installer (gdisk-v3-installer.exe)

| Image | Format | Description |
|---|---|---|
| [gdisk-v3-installer.exe](https://github.com/GlitchLinux/Gdisk/releases/download/Gdisk-v3.0/gdisk-v3-installer.exe) | Portable Windows Executable | GUI Installer |

A portable GUI installer for Windows and WinPE. Everything is self-contained - `wget.exe`, `7z.exe` and a cross-compiled `grub-bios-setup.exe` are all embedded. No installation or external dependencies required.

The installer fetches the latest Gdisk build from GitHub, partitions and formats the target with `diskpart`, deploys the files, and installs the BIOS + UEFI boot chain. Works on physical drives and mounted virtual disks - anything `diskpart` can see.

Operations:

- **Create Gdisk device** - Format the target disk as MBR/FAT32 and deploy Gdisk
- **Update / Repair** - Reinstall the MBR boot chain and refresh boot files (`boot/` and `EFI/`), preserving user data

**Note:** Run as Administrator. In WinPE, the installer works out of the box since WinPE runs with full privileges.

### Method 4 - iPXE Network Boot (no local media needed)

| Image | Format | Description |
|---|---|---|
| [Gdisk-ISO-v3.2-iPXE.iso](https://github.com/GlitchLinux/Gdisk/releases/download/Gdisk-v3.2/Gdisk-ISO-v3.2-iPXE.iso) | Bootable ISO | iPXE boots Debian minimal live, auto-launches `gdisk-v3.sh` |
| [Gdisk-v3-Installer-iPXE.img](https://github.com/GlitchLinux/Gdisk/releases/download/Gdisk-v3.0/gdisk-v3-installer-ipxe-efi.img) | EFI Partition Image | iPXE boots Debian minimal live, auto-launches `gdisk-v3.sh` |

For situations where you don't have a working Linux or Windows environment available, or you want to install Gdisk to the same disk you're booting from.

iPXE images boot a minimal Debian live system entirely into RAM via network boot. Once booted, the Gdisk installer runs automatically. Because the OS is running from RAM, the target disk is completely free - you can install Gdisk to the very disk you booted from.

**Requirements:** Wired internet connection (Ethernet). The iPXE boot image must be flashed to a USB stick or disk first using any raw image writer (dd, Rufus, Etcher, etc).

**iPXE install workflow:**

1. Download the iPXE ISO image
2. Launch in Virtual-Machine OR: 
3. Flash it to a USB stick using dd, Rufus, Etcher or similar:
   ```bash
   sudo dd if=Gdisk-ISO-v3.2-iPXE.iso of=/dev/sdX bs=4M status=progress
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
routes each `.iso`, `.img`, `.wim`, `.vhd`, `.vhdx` or `.vtoy` to the appropriate
pre-boot handler.

### VHD / VHDX boot

Drop `.vhd` or `.vhdx` files into the root, `/VHD/` or `/Gdisk/` of any attached
partition and pick **VHD / VHDX Boot** from the main menu, or reach them through the
browser or the Quickboot menu.

Boot methods offered per image:

| Method | Platform | Container support |
|---|---|---|
| **ntloader** (preferred) | BIOS + UEFI | fixed and dynamic VHD, VHDX |
| ntloader `ram=` (load to RAM) | BIOS + UEFI | fixed and dynamic VHD, VHDX |
| `ntboot --vhd` (native NT6+ boot) | UEFI + BIOS | fixed and dynamic VHD, VHDX |
| `map --type=HD` / `map -f` | UEFI | fixed VHD only |
| grub4dos `map` | BIOS | fixed VHD only |
| memdisk raw (loads to RAM) | BIOS | fixed VHD only |
| vDiskChain | UEFI + BIOS | fixed VHD only |

Native boot uses the Windows Boot Manager, so two host-volume constraints apply:

- **The VHD should live on an NTFS volume.** `bootmgr` attaches the VHD with its own
  filesystem drivers plus `bootvhd.dll`, and does not mount VHDs from FAT32 or exFAT.
- **FAT32 caps single files at 4 GiB.** Gdisk's own partition is FAT32, so anything
  larger than 4 GiB has to sit on a separate NTFS partition. The installer's
  **FAT32 + NTFS** layout provides this out of the box.

### Why ntloader is preferred for BIOS

On UEFI, `bootmgfw.efi` has VHD support compiled in. On BIOS, `bootmgr` must load
`\boot\bootvhd.dll` to attach the VHD, and Windows boot modules are version-locked:
a mismatched `bootmgr` / `bootvhd.dll` pair is rejected with Windows Boot Manager
status `0xc0000098` (`STATUS_FILE_INVALID`). ntloader ships its own `initrd.cpio`
containing a matched 10.0.20348 set (`bootmgr.exe`, `bootvhd.dll`, `boot.sdi`,
`bootx64.efi`), which avoids the problem entirely.

The `ntboot` entries remain as a fallback. They use `bootmgr-nt11.exe`
(10.0.22621.2283) paired with `bootvhd.dll` (10.0.22621.1555) rather than the older
`bootmgr.exe` (10.0.19041.1), which is kept only for the BIOS WIM boot path.

Supporting files live in `boot/grub/ntloader/` (ntloader binaries plus `initrd.cpio`)
and `boot/grub/wimboot/` (`wimboot.xz` holding `bootmgfw.efi` for UEFI, plus
`bootmgr.exe`, `bootmgr-nt11.exe`, `bootvhd.dll` and `boot.sdi` for BIOS).

You can also test a device without rebooting using the bundled QEMU launcher. It boots the
physical disk Gdisk is installed on and asks whether to use BIOS (SeaBIOS) or UEFI (OVMF):

```bash
./Qemu-Boot.sh     # choose BIOS or UEFI (UEFI requires: apt install ovmf)
```

The standalone `qemu-bios.sh` and `qemu-uefi.sh` scripts remain in `boot/Gdisk-Scripts/`.

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
