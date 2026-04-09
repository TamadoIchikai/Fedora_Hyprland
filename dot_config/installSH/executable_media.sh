#!/usr/bin/env bash
set -euo pipefail

echo -e "${BLUE}-------> Install waybar and related modules ${NC}"

sudo dnf copr enable -y erikreider/SwayNotificationCenter
sudo dnf install -y waybar blueman pavucontrol zenity SwayNotificationCenter mpv mpv-mpris playerctl ufw

flatpak install -y flathub org.localsend.localsend_app

sudo firewall-cmd --add-port=53317/tcp --add-port=53317/udp --permanent
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports

echo -e "${GREEN}-------> DONE ${NC}"