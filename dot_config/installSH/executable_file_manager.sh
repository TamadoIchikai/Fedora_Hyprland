#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

set -e
echo -e "${BLUE}-------> Installing Thunar file manager${NC}"
sudo dnf install -y thunar thunar-archive-plugin thunar-volman gsettings-desktop-schemas gnome-themes-extra
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'
echo -e "${GREEN}-------> DONE${NC}"

