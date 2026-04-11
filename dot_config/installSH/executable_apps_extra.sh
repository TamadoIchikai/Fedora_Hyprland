#!/usr/bin/env bash
set -euo pipefail

echo -e "${BLUE}-------> Installing brave browser${NC}"
curl -fsS https://dl.brave.com/install.sh | sh

echo -e "${BLUE}-------> Installing flatpak apps (OBS)${NC}"
sudo dnf install -y flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub com.obsproject.Studio

echo -e "${GREEN}-------> DONE${NC}"
