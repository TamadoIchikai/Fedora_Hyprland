#!/usr/bin/env bash
set -euo pipefail

echo ">>>  Installing wifi firmwares..."
sudo dnf install iwlwifi\*

echo ">>>  Installing kernel dev for Nvidia drivers..."
sudo dnf install kernel-devel kernel-headers gcc make dkms acpid libglvnd-glx libglvnd-opengl libglvnd-devel pkgconfig
echo ">>>  Adding non free repo in to fedora..."
sudo dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm\
sudo dnf install https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf makecache
echo ">>> Installing nvidia driver..."
sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda
echo ">>> Done!!"
