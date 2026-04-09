#!/usr/bin/env bash
set -euo pipefail

echo -e "${BLUE}-------> Installing brave browser${NC}"
curl -fsS https://dl.brave.com/install.sh | sh

echo -e "${BLUE}-------> Installing flatpak apps (Obsidian, Zotero, LocalSend)${NC}"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub md.obsidian.Obsidian
flatpak install -y flathub org.zotero.Zotero
flatpak install -y flathub org.localsend.localsend_app

echo -e "${GREEN}-------> DONE${NC}"