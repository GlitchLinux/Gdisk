#!/bin/bash

sudo rm -f /tmp/.vtoy-live.sh wget-log

set PWD=pwd

echo "tree $PWD" > /tmp/path

cat > "/tmp/.vtoy-live.sh" << 'EOF'

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

echo " Downloaded Files: " | borderize > /tmp/wget-result
echo "" >> /tmp/wget-result
mv -f Vtoy-WinPE-Download.sh /tmp/
rm -f .ventoyignore
bash /tmp/path >> /tmp/wget-result
cp /tmp/Vtoy-WinPE-Download.sh .
touch .ventoyignore
clear
echo "" 
echo "" >> /tmp/wget-result
echo "WinPE-Vtoy files sucessfully downloaded!" >> /tmp/wget-result
echo "" >> /tmp/wget-result

xterm -geometry 47x17 -e "cat /tmp/wget-result && sleep 60"

EOF

xterm -geometry 60x5 -e 'sudo bash /tmp/.vtoy-live.sh' 2>&1 &
sleep 0.5 && sudo pkill xfce4-terminal
exit

