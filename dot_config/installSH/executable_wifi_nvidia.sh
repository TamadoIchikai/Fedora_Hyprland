#!/usr/bin/env bash
set -euo pipefail

echo -e "${BLUE}>>> Installing wifi firmwares...${NC}"
sudo dnf install -y iwlwifi\*

echo -e "${BLUE}>>> Installing kernel dev for Nvidia drivers...${NC}"
sudo dnf install -y kernel-devel kernel-headers gcc make dkms acpid libglvnd-glx libglvnd-opengl libglvnd-devel pkgconfig

echo -e "${BLUE}>>> Adding non free repo in to fedora...${NC}"
sudo dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
sudo dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
sudo dnf makecache

echo -e "${BLUE}>>> Installing nvidia driver...${NC}"
sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
echo -e "${GREEN}>>> Done!!${NC}"