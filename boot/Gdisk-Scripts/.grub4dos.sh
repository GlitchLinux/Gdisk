#!/bin/bash

clear

sudo rm -f /tmp/grub4dos-generate

cat > "/tmp/grub4dos-generate" << 'EOF'

cat boot/Gdisk-Installer/gdisk.ascii | /usr/games/lolcat
PATH boot/Gdisk-Scripts/ > /tmp/gdisk-path
GPATH=$(< /tmp/gdisk-path)

cd "$GPATH" || exit 1

sudo cp .gen-menulst.sh ../..
cd ../.. || exit 1
sudo bash .gen-menulst.sh . > /tmp/grub4dos-list
sudo rm .gen-menulst.sh

echo
cat /tmp/grub4dos-list
echo ""

echo  "  ~  SCRIPT WILL AUTO-EXIT IN 15 SECONDS  ~  " > /tmp/grub4dos-list

cat /tmp/grub4dos-list | borderize

sleep 15 

sudo rm -f /tmp/grub4dos-generate

exit

EOF

xterm -geometry 55x18 -e 'bash "/tmp/grub4dos-generate"' &
