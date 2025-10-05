#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -e
echo -e "${BLUE}-------> install waybar and some related modules ${NC}"
sudo dnf enable erikreider/SwayNotificationCenter
sudo dnf install waybar kde-connect blueman pavucontrol zenity SwayNotificationCenter mpv mpv-mpris playerctl
echo -e "${GREEN}-------> DONE ${NC}"

