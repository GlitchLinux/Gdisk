#!/bin/bash

set PWD=pwd

echo "cat /tmp/download-job | borderize ; read -p '  ' " > /tmp/finished 

cat > "/tmp/.bootfiles-download.sh" << 'EOF'

sudo rm -f *.vtoy 
sudo rm -f *.wim
echo "Downloading WinPE Vtoy - EaseUS_Partition_Pro" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/WinPE-Vtoy/EaseUS_Partition_Pro.vtoy"
clear
echo "Downloading WinPE Vtoy - Diskgenius-Pro-v6" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/WinPE-Vtoy/Diskgenius-Pro-v6.vtoy"
clear
echo "Downloading WinPE Wim - NanoTech-11-x64-v1.8" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/NanoTech-11-x64/NanoTech-11-x64-v1.8-25-July-2026.wim"
sudo mv NanoTech-11-x64-v1.8-25-July-2026.wim NanoTech-11-x64-v1.8.wim

echo "All Files Sucessfully Downloaded!" > /tmp/download-job
echo "  Hit enter to finish script" >> /tmp/download-job

xterm -geometry 39x5 -e "bash /tmp/finished"

sudo rm -f .bootfiles-download.sh

EOF

sudo mv "/tmp/.bootfiles-download.sh" .

xterm -geometry 60x5 -e 'sudo bash .bootfiles-download.sh' 2>&1 &

sleep 0.5 && sudo pkill xfce4-terminal

exit
