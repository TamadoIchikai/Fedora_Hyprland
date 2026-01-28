#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -e
echo -e "${BLUE}-------> Install core for my hyprland config ${NC}"
sudo dnf copr enable lionheartp/Hyprland 
sudo dnf install hyprland hyprlock hyprshutdown swaybg hyprsunset vim neovim fastfetch flatpak meson cmake
echo -e "${GREEN}-------> Done${NC}"

