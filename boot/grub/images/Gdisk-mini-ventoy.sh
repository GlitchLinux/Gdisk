#!/bin/bash

sudo rm -f /tmp/.mini-ventoy Gdisk-3.2-Ventoy.img

cat > /tmp/.mini-ventoy << 'EOF'
#!/bin/bash
cd /tmp && sudo rm -rf ventoy-1.1.17/ ventoy-1.1.17-linux.tar.gz
sudo wget -q https://glitchlinux.wtf/FILES/GLITCH-SOFTWARE/gdisk-mini-ventoy/ventoy-1.1.17-linux.tar.gz
sudo tar -xvf ventoy-1.1.17-linux.tar.gz
sudo bash /tmp/ventoy-1.1.17/Gdisk-mini-ventoy.sh
EOF

sudo chmod +x /tmp/.mini-ventoy
sudo bash /tmp/.mini-ventoy
sudo cp -f /tmp/Gdisk-3.2-Ventoy.img .
