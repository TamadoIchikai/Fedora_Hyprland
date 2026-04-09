#!/usr/bin/env bash
set -euo pipefail

echo -e "${BLUE}-------> Install core for my hyprland config ${NC}"
sudo dnf copr enable -y lionheartp/Hyprland 
sudo dnf install -y hyprland hyprlock hyprshutdown swaybg hyprsunset hyprland-guiutils vim neovim fastfetch flatpak meson cmake
echo -e "${GREEN}-------> Done${NC}"