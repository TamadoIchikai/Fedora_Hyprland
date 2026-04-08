#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -e
echo -e "${BLUE}-------> Install some bloatwares lmao${NC}"
sudo dnf copr enable dejan/lazygit
sudo dnf install foot fuzzel fzf zoxide cliphist fuse fuse-libs qalculate setxkbmap trash-cli swappy btop lazygit duf gdu swayimg xournalpp lua-lgi nm-connection-editor

echo -e "${BLUE}------->install brave browser${NC}"
curl -fsS https://dl.brave.com/install.sh | sh

echo -e "${BLUE}------->install flatpak related apps like obsidian, mission center${NC}"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub md.obsidian.Obsidian
flatpak install flathub org.zotero.Zotero
flatpak install flathub org.localsend.localsend_app

echo -e "${GREEN}-------> DONE${NC}"

