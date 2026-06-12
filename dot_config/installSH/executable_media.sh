#!/usr/bin/env bash
set -euo pipefail

sudo dnf copr enable -y erikreider/SwayNotificationCenter
sudo dnf install -y waybar blueman pavucontrol zenity SwayNotificationCenter mpv mpv-mpris playerctl

sudo firewall-cmd --add-port=53317/tcp --add-port=53317/udp --permanent
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports
