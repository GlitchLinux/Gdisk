#!/bin/bash

sudo rm -f vmlinuz* filesystem.squashfs* initrd.img* wget-log

sudo rm -f /tmp/.glitch-live.sh

set PWD=pwd

echo "tree $PWD" > /tmp/path

cat > "/tmp/.glitch-live.sh" << 'EOF'

echo "Downloading Glitch-Linux Live v34 - initrd.img" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v34/live/initrd.img"
clear
echo "Downloading Glitch-Linux Live v34 - vmlinuz" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v34/live/vmlinuz"
clear
echo "Downloading Glitch-Linux Live v34 - filesystem.squashfs" | borderize
echo ""
sudo wget -q --show-progress "https://glitchlinux.wtf/ipxe/Glitch-Linux-v34/live/filesystem.squashfs"

echo " Downloaded Files: " | borderize > /tmp/wget-result
echo "" >> /tmp/wget-result
mv -f Glitch-v34-Live-Download.sh /tmp/
rm -f .ventoyignore
bash /tmp/path >> /tmp/wget-result
cp /tmp/Glitch-v33-Live-Download.sh .
touch .ventoyignore
clear
echo "" 
echo "" >> /tmp/wget-result
echo "Glitch Linux v33 Sucessfully Downloaded!" >> /tmp/wget-result
echo "" >> /tmp/wget-result

xterm -geometry 47x17 -e "cat /tmp/wget-result && sleep 120"

EOF

xterm -geometry 60x5 -e 'sudo bash /tmp/.glitch-live.sh' 2>&1 &
sleep 0.5 && sudo pkill xfce4-terminal
exit
