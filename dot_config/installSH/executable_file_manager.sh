#!/usr/bin/env bash
set -euo pipefail

echo -e "${BLUE}-------> Installing Thunar file manager and dependencies${NC}"

sudo dnf install -y \
thunar thunar-archive-plugin thunar-volman \
gvfs gvfs-fuse udisks2 \
tumbler \
xarchiver file-roller unzip p7zip p7zip-plugins unrar \
dconf gsettings-desktop-schemas \
gnome-themes-extra papirus-icon-theme \
shared-mime-info xdg-utils desktop-file-utils \
evince-thumbnailer ffmpegthumbnailer \
xdg-desktop-portal xdg-desktop-portal-gtk

sleep 1
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'
sleep 1

echo -e "${BLUE}-------> Setting default applications${NC}"

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

xdg-mime default nautilus.desktop inode/directory

sudo update-desktop-database
sudo update-mime-database /usr/share/mime

echo -e "${GREEN}-------> DONE${NC}"
