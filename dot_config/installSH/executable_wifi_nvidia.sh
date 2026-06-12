#!/usr/bin/env bash
set -euo pipefail

echo "Installing Intel Wi-Fi drivers..."
sudo dnf install -y iwlwifi\*

echo ""
read -r -p "Do you want to install the Nvidia drivers and dependencies? (y/N): " install_nvidia

if [[ "$install_nvidia" =~ ^[Yy]$ ]]; then
    echo "Installing build dependencies..."
    sudo dnf install -y kernel-devel kernel-headers gcc make dkms acpid libglvnd-glx libglvnd-opengl libglvnd-devel pkgconfig

    echo "Adding RPM Fusion repositories..."
    sudo dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
    sudo dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
    sudo dnf makecache

    echo "Installing Nvidia driver (580xx)..."
    sudo dnf install -y akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx xorg-x11-drv-nvidia-580xx-cuda
    
    echo "Building kernel modules and updating initramfs..."
    sudo akmods --force
    sudo dracut --force
    
    echo "Nvidia drivers installed successfully."
else
    echo "Skipping Nvidia driver installation."
fi
