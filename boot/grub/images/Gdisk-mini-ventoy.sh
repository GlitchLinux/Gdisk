#!/bin/bash

cd /tmp && sudo rm -rf ventoy-1.1.17/ ventoy-1.1.17-linux.tar.gz
sudo wget -q https://glitchlinux.wtf/FILES/GLITCH-SOFTWARE/gdisk-mini-ventoy/ventoy-1.1.17-linux.tar.gz
sudo tar -xvf ventoy-1.1.17-linux.tar.gz
cd ventoy-1.1.17/ && sudo bash Gdisk-mini-ventoy.sh
cd ~