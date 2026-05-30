#!/usr/bin/env bash
set -euo pipefail

#echo -e "${BLUE}-------> Installing brave browser${NC}"
#curl -fsS https://dl.brave.com/install.sh | sh

echo -e "${BLUE}-------> Install xournal dev via luya copr${NC}"
sudo dnf copr enable -y luya/xournalpp
sudo dnf install -y lua-lgi xournalpp keepassxc
echo -e "${GREEN}-------> DONE${NC}"

echo -e "${BLUE}-------> Install libre wolf as a secondary browser${NC}"
sudo dnf config-manager addrepo --from-repofile=https://repo.librewolf.net/librewolf.repo
sudo dnf install -y librewolf
echo -e "${GREEN}-------> DONE${NC}"

echo -e "${BLUE}-------> Installing flatpak apps (OBS)${NC}"
sudo dnf install -y flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub com.obsproject.Studio
flatpak install -y flathub io.github.mpc_qt.mpc-qt

echo -e "${GREEN}-------> DONE${NC}"
