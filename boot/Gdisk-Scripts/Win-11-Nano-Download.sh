#!/bin/bash
clear
which lolcat > /tmp/.lolcat && sudo chmod +x /tmp/.lolcat
cat ../Gdisk-Installer/gdisk.ascii | /tmp/.lolcat
echo ""
cd .. && cd ..
cd Gdisk
sudo rm -rf WinPE-Teal-Installer-v1.5.iso
echo "Downloading WinPE-Teal-Installer-v1.5.iso"
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/FILES/Windows-Installers/WinPE-Teal-Installer-v1.5.iso"
clear
echo "WinPE-Teal-Installer-v1.5.iso Downloaded successfully!"
read -p ' '
