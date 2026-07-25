## Gdisk - Grub2 MultiBoot

<img width="1280" height="360" alt="FullLogo_NoBuffer" src="https://github.com/user-attachments/assets/1080118d-18ac-4d28-9399-16b29014b5d7" />


```
    .aMMMMP   dMMMMb    dMP   .dMMMb    dMP dMP 
   dMP"      dMP VMP   amr   dMP" VP   dMP dMP  
  dMP MMP"  dMP dMP   dMP    VMMMb    dMMMM"   
 dMP.dMP   dMP.aMP   dMP   dP .dMP   dMP"AMF    
 VMMMP"   dMMMMP"   dMP    VMMMP"   dMP dMP     
 
 Grub2   Device   Image   System     Kit             
```

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
│   ├── Gdisk-Installer/      shipped installers: gdisk-v3.sh, gdisk-v3.exe, wget.exe
│   └── Gdisk-Mkiso/          ISO-build scripts: gdisk-mkiso.sh, gdisk-hybrid-iso.sh
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

The installers are self-contained and also ship inside the device at
`boot/Gdisk-Installer/`.

### Linux

`gdisk-v3.sh` deploys Gdisk to a disk or partition, preserving the patched a1ive
`core.img` boot chain (installed from the prebuilt `core-patched.img` via
`grub-bios-setup`, never regenerated, so the custom modules survive):

- **Create** - wipe a whole disk, write a new MBR table + sized FAT32, deploy files,
  install BIOS + UEFI boot
- **Update** - refresh Gdisk onto an existing partition
- **Repair** - reinstall the MBR core.img and/or UEFI `BOOTX64.EFI`

```bash
sudo ./gdisk-v3.sh
```

### Windows / WinPE

`gdisk-v3-installer.exe` is a portable installer that runs on Windows and inside WinPE
with no external dependencies - `wget`, `7z` and a cross-compiled `grub-bios-setup.exe`
are embedded as resources. It fetches the latest Gdisk build from GitHub, partitions
and formats the target with `diskpart`, copies the files, and installs the BIOS + UEFI
boot chain. Works on physical drives and mounted virtual disks (anything `diskpart`
lists).

- **Create Gdisk device** - format the disk as MBR/FAT32 and deploy Gdisk
- **Update & Repair** - reinstall the MBR boot chain and refresh the boot files
  (`boot/` and `EFI/`), preserving user data

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
boot/Gdisk-Mkiso/gdisk-mkiso.sh
boot/Gdisk-Mkiso/gdisk-hybrid-iso.sh
```

---

## Related

- **grub2-patch** - the patched GrubFM-derived modules that enable raw UEFI
  loopback booting: https://github.com/GlitchLinux/grub2-patch

---

Source: https://github.com/GlitchLinux  ·  GPLv3
