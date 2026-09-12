#!/bin/bash

clear
cat ../Gdisk-Installer/gdisk.ascii | /usr/games/lolcat
echo ""
cd .. && cd ..
cd Gdisk
sudo mkdir -p glitch-live
cd glitch-live

sudo rm -rf initrd.img
sudo rm -rf vmlinuz
sudo rm -rf filesystem.squashfs

echo "Downloading Glitch-Linux v43 Live System"
echo ""

sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v43/live/initrd.img"
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v43/live/vmlinuz"
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v43/live/filesystem.squashfs"

clear

cd .. && cd boot/Gdisk-Installer && cat gdisk.ascii | /usr/games/lolcat

echo ""

echo "Glitch-Linux-v43 Live-Boot Downloaded!" 

read -p ' '
