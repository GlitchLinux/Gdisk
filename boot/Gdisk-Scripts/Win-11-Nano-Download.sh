#!/bin/bash
clear
cat ../Gdisk-Installer/gdisk.ascii | lolcat
echo ""
cd .. && cd ..
cd Gdisk
sudo rm -rf Win-11-Nano-Installer-v8.iso
echo "Downloading Win-11-Nano-Installer-v8.iso"
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/FILES/Windows-Installers/Win-11-Nano-Installer-v8.iso"
clear
echo "Win-11-Nano-Installer-v8.iso Downloaded successfully!" 
read -p ' '

