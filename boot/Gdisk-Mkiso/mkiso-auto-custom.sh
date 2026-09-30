#!/bin/bash

sudo bash .mkiso-auto-custom.sh
sudo mv /Gdisk-v3.iso /tmp/Gdisk-v3.2.iso
sudo rm -f /efi.img
echo ""
echo "ISO Build saved to: /tmp/Gdisk-v3.2.iso" | borderize 
echo ""
read p