#!/bin/bash

xterm -geometry 70x15 -e 'echo "gdisk grub4dos autogen boot-entries" | borderize && sudo bash boot/grub/.gen-menulst.sh . && sleep 5'
