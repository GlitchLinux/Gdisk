#!/bin/bash

clear
which lolcat > /tmp/.lolcat && sudo chmod +x /tmp/.lolcat
cp ../Gdisk-Installer/gdisk.ascii /tmp/.gdisk.ascii
cat /tmp/.gdisk.ascii | /tmp/.lolcat

echo ""
cd .. && cd ..
cd Gdisk
sudo mkdir -p glitch-live
cd glitch-live

sudo rm -rf initrd.img
sudo rm -rf vmlinuz
sudo rm -rf filesystem.squashfs

echo "Downloading Glitch-Linux v45 Live System"
echo ""

sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v45/live/initrd.img"
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v45/live/vmlinuz"
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v45/live/filesystem.squashfs"

echo "#╭──────────────────╮" > glitch.info
echo "#│ Glitch-Linux-v45 │" >> glitch.info
echo "#╰──────────────────╯" >> glitch.info

clear

cat /tmp/.gdisk.ascii | /tmp/.lolcat

echo ""

echo "Glitch-Linux-v45 Live-Boot Downloaded!" 

read -p ' '
