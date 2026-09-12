#!/bin/bash
clear
cat ../Gdisk-Installer/gdisk.ascii | /usr/games/lolcat
echo ""
cd .. && cd ..
cd Gdisk
sudo rm -rf WinPE-Teal-Installer-v1.4.iso
echo "Downloading WinPE-Teal-Installer-v1.4.iso"
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/FILES/Windows-Installers/WinPE-Teal-Installer-v1.4.iso"
clear
echo "WinPE-Teal-Installer-v1.4.iso Downloaded successfully!"
read -p ' '
