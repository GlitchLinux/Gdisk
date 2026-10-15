#!/bin/bash

clear
which lolcat > /tmp/.lolcat && sudo chmod +x /tmp/.lolcat
cp ../Gdisk-Installer/gdisk.ascii /tmp/.gdisk.ascii
cat /tmp/.gdisk.ascii | /tmp/.lolcat

echo ""
cd .. && cd ..
cd Gdisk && cd ..
sudo mkdir -p glitch-live
cd glitch-live

sudo rm -rf initrd.img
sudo rm -rf vmlinuz
sudo rm -rf filesystem.squashfs

echo "Downloading Glitch-Linux Live System"
echo ""

sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-Live/live/initrd.img"
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-Live/live/vmlinuz"
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-Live/live/filesystem.squashfs"
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-Live/live/glitch.info"

cat glitch.info > /tmp/.glitch.info

clear

cat /tmp/.gdisk.ascii | /tmp/.lolcat

echo "Release version:"
echo ""
cat /tmp/.glitch.info && rm /tmp/.glitch.info
echo ""

echo "Glitch-Linux Live Downloaded!" 

read -p ' '
