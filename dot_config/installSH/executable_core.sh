#!/usr/bin/env bash
set -euo pipefail

sudo dnf copr enable -y lionheartp/Hyprland 
sudo dnf install -y hyprland hyprlock wlsunset swaybg hyprland-guiutils vim neovim fastfetch meson cmake flatpak
