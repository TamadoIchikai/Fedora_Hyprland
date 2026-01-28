#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -e
echo -e "${BLUE}-------> install waybar and some related modules ${NC}"
sudo dnf copr enable erikreider/SwayNotificationCenter
sudo dnf install -y waybar blueman pavucontrol zenity SwayNotificationCenter mpv mpv-mpris playerctl ufw
flatpak install flathub org.localsend.localsend_app
sudo firewall-cmd --add-port=53317/tcp --add-port=53317/udp --permanent
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports
echo -e "${GREEN}-------> DONE ${NC}"

