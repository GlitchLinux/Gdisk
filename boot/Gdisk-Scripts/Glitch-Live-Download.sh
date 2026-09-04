#!/bin/bash

clear
cat ../Gdisk-Installer/gdisk.ascii | lolcat
echo ""
cd .. && cd ..
cd Gdisk
sudo mkdir -p glitch-live
cd glitch-live

sudo rm -rf initrd.img
sudo rm -rf vmlinuz
sudo rm -rf filesystem.squashfs

echo "Downloading Glitch-Linux v42 Live System"
echo ""

sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v42/live/initrd.img"
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v42/live/vmlinuz"
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v42/live/filesystem.squashfs"

clear

cat ../Gdisk-Installer/gdisk.ascii | lolcat

echo "Glitch-Linux-v42 Live-Boot Downloaded!" 

read -p ' '
