#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

echo -e "${BLUE}-------> install zig for ly ${NC}"
sudo dnf install kernel-devel pam-devel libxcb-devel xorg-x1-xauth xorg-x11-server-Xorg brightnessctl
cd ~/Downloads/Systems/
wget https://ziglang.org/download/0.15.1/zig-x86_64-linux-0.15.1.tar.xz
tar -xf Downloads/Systems/zig-x86_64-linux-0.15.1.tar.xz
mv zig-x86_64-linux-0.15.1/ zig
rm zig-x86_64-linux-0.15.1.tar.xz
sudo ln -s ~/Downloads/Systems/zig/zig /usr/local/bin/zig
echo "Zig version: $(zig -v)"
echo -e "${GREEN}-------> DONE${NC}"

echo -e "${BLUE}-------> begin download ly and build the project ${NC}"
cd ~/Downloads/Systems/
git clone https://codeberg.org/fairyglade/ly.git
cd ly/
sudo zig build installexe -Dinit_system=systemd
sudo systemctl disable getty@tty2.service
sudo systemctl disable getty@tty1.service
sudo systemctl enable ly.service
sudo systemctl set-default graphical.target
echo -e "${GREEN}-------> DONE${NC}"
