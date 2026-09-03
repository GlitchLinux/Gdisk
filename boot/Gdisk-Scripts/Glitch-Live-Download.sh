#!/bin/bash

cd ..
cd ..
sudo mkdir -p glitch-live
cd glitch-live

sudo rm -rf initrd.img
sudo rm -rf vmlinuz
sudo rm -rf filesystem.squashfs

clear

echo "Downloading Glitch-Linux-v42 initrd.img"
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v42/live/initrd.img"
clear
echo "Downloading Glitch-Linux-v42 vmlinuz"
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v42/live/vmlinuz"
clear
echo "Downloading Glitch-Linux-v42 filesystem.squashfs"
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v42/live/filesystem.squashfs"

clear

echo "Glitch-Linux-v42 Live-Boot Downloaded!" 

read -p ' '
