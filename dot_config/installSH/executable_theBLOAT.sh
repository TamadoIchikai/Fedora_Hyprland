#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -e
echo -e "${BLUE}-------> Install some bloatwares lmao${NC}"
sudo dnf install foot fuzzel fzf zsh firefox

echo "${BLUE}------->install flatpak related apps like obsidian, mission center${NC}"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub io.missioncenter.MissionCenter
flatpak override --user --socket=system-bus org.missioncenter.MissionCenter
flatpak install flathub it.mijorus.gearlever

echo "${BLUE}-------> install minimal cargo for some app like zoxide${NC}"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile=minimal
source ~/.bashrc
cargo install zoxide --locked

echo "${BLUE}------->Building rofi for wayland support${NC}"
sudo dnf install cairo-devel pango-devel glib2-devel libxkbcommon-devel wayland-devel wayland-protocols-devel pkg-config meson cmake rofi-devel qalc
cd ~/Downloads/Systems/
git clone https://github.com/svenstaro/rofi-calc.git
cd rofi-calc/
meson setup build
cd build
ninja
sudo ninja install
cd

echo "${BLUE}-------> Set default application${NC}"
xdg-mime default swayimg.desktop image/jpeg
xdg-mime default swayimg.desktop image/png
xdg-mime default swayimg.desktop image/gif
xdg-mime default swayimg.desktop image/webp
xdg-mime default swayimg.desktop image/svg+xml
xdg-mime default swayimg.desktop image/avif
xdg-mime default swayimg.desktop image/avifs
xdg-mime default vlc.desktop video/mpeg
xdg-mime default vlc.desktop video/ogg
xdg-mime default vlc.desktop video/webm
xdg-mime default vlc.desktop video/mp4
xdg-mime default vlc.desktop audio/mpeg        
xdg-mime default vlc.desktop audio/mp4         
xdg-mime default vlc.desktop audio/ogg

xdg-mime default thunar.desktop inode/directory

echo -e "${GREEN}-------> DONE${NC}"
