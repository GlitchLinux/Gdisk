#!/bin/bash

sudo rm -f vmlinuz* filesystem.squashfs* initrd.img* wget-log

sudo rm -f /tmp/.bonsai-live.sh

set PWD=pwd

echo "tree $PWD" > /tmp/path

cat > "/tmp/.bonsai-live.sh" << 'EOF'

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

echo " Downloaded Files: " | borderize > /tmp/wget-result
echo "" >> /tmp/wget-result
mv -f Bonsai-Xfce-v15-Download.sh /tmp/
rm -f .ventoyignore
bash /tmp/path >> /tmp/wget-result
cp /tmp/Bonsai-Xfce-v15-Download.sh .
touch .ventoyignore
clear
echo "" 
echo "" >> /tmp/wget-result
echo "Bonsai Live v15 - Sucessfully Downloaded!" >> /tmp/wget-result
echo "" >> /tmp/wget-result

xterm -geometry 47x17 -e "cat /tmp/wget-result && sleep 120"

EOF

xterm -geometry 60x5 -e 'sudo bash /tmp/.bonsai-live.sh' 2>&1 &
sleep 0.5 && sudo pkill xfce4-terminal
exit
