#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -e
echo -e "${BLUE}-------> Install some bloatwares lmao${NC}"
sudo dnf install foot fuzzel fzf zsh firefox zoxide cliphist fuse fuse-libs qalculate

echo -e "${BLUE}------->install flatpak related apps like obsidian, mission center${NC}"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub io.missioncenter.MissionCenter
flatpak install flathub md.obsidian.Obsidian

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
xdg-mime default code.desktop text/plain
xdg-mime default code.desktop text/x-python
xdg-mime default code.desktop text/x-c
xdg-mime default code.desktop text/x-c++src
xdg-mime default code.desktop text/html
xdg-mime default code.desktop text/css
xdg-mime default code.desktop application/javascript
xdg-mime default code.desktop application/json
xdg-mime default code.desktop text/markdown
xdg-mime default code.desktop application/x-shellscript
xdg-mime default code.desktop text/yaml
xdg-mime default code.desktop application/xml
xdg-mime default thunar.desktop inode/directory

echo -e "${GREEN}-------> DONE${NC}"
