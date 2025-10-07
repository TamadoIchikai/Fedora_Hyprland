#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -e
echo -e "${BLUE}-------> install waybar and some related modules ${NC}"
sudo dnf copr enable erikreider/SwayNotificationCenter
sudo dnf install -y waybar kde-connect blueman pavucontrol zenity SwayNotificationCenter mpv mpv-mpris playerctl ufw
sudo ufw enable
sudo firewall-cmd --permanent --add-port=1714-1764/tcp
sudo firewall-cmd --permanent --add-port=1714-1764/udp
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports
sudo ufw allow 1714:1764/udp comment "Allow KDE Connect UDP"
sudo ufw allow 1714:1764/tcp comment "Allow KDE Connect TCP"
echo -e "${GREEN}-------> DONE ${NC}"

