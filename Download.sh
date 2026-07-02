#!/bin/bash

set PWD=pwd

sudo rm -f .bootfiles-download.sh

echo "cat /tmp/download-job | borderize ; read -p '  ' " > /tmp/finished 

cat > "/tmp/.bootfiles-download.sh" << 'EOF'

cd Gdisk
sudo rm -f *.vtoy
echo "Downloading WinPE Vtoy - EaseUS_Partition_Pro" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/WinPE-Vtoy/EaseUS_Partition_Pro.vtoy"
clear
echo "Downloading WinPE Vtoy - Diskgenius-Pro-v6" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/WinPE-Vtoy/Diskgenius-Pro-v6.vtoy"
clear
echo "Downloading WinPE Vtoy - MiniWin-10-WinPE" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/WinPE-Vtoy/MiniWin-10-WinPE.vtoy"
clear
echo "Downloading WinPE Vtoy - MicroTech-11-WinPE" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/FILES/Windows-PE/WinPE-Vtoy/MicroTech-11-WinPE.vtoy"
clear
echo "Downloading WinPE Vtoy - Tiny-11-WinPE" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/FILES/winpe-vtoy/Tiny-11-WinPE.vtoy"

cd ..
cd bonsai-live
sudo rm -f vmlinuz initrd.img filesystem.squashfs

echo "Downloading Bonsai Live v15 - initrd.img" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Bonsai-Xfce-v15/live/initrd.img"
clear
echo "Downloading Bonsai Live v15 - vmlinuz" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Bonsai-Xfce-v15/live/vmlinuz"
clear
echo "Downloading Bonsai Live v15 - filesystem.squashfs" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Bonsai-Xfce-v15/live/filesystem.squashfs"

cd ..
cd glitch-live
sudo rm -f vmlinuz initrd.img filesystem.squashfs

echo "Downloading Glitch-Linux Live v38 - initrd.img" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v38/live/initrd.img"
clear
echo "Downloading Glitch-Linux Live v38 - vmlinuz" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v38/live/vmlinuz"
clear
echo "Downloading Glitch-Linux Live v38 - filesystem.squashfs" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v38/live/filesystem.squashfs"

echo "All Files Sucessfully Downloaded!" > /tmp/download-job
echo "  Hit enter to finish script" >> /tmp/download-job

xterm -geometry 39x5 -e "bash /tmp/finished"

sudo rm -f .bootfiles-download.sh

EOF

sudo mv "/tmp/.bootfiles-download.sh" .

xterm -geometry 60x5 -e 'sudo bash .bootfiles-download.sh' 2>&1 &

sleep 0.5 && sudo mv -f Download.sh .Download.sh && sudo pkill xfce4-terminal

exit
