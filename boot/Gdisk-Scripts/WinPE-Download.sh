#!/bin/bash

clear
cat ../Gdisk-Installer/gdisk.ascii | lolcat
echo ""
cd .. && cd ..
cd Gdisk
sudo rm -rf MultiTech-11-X64-v2.6.wim
echo "Downloading MultiTech-11-X64-v2.6.wim"
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/MultiTech-11-x64/MultiTech-11-X64-v2.6.wim"
clear
echo "MultiTech-11-X64-v2.6.wim Downloaded successfully!" 
read -p ' '
