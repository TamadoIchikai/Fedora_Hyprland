#!/usr/bin/env bash
# Intel Wi-Fi firmware + optional Nvidia driver (RPM Fusion, 580xx branch).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

info "Installing Intel Wi-Fi drivers..."
dnf_install 'iwlwifi*'

echo ""
read -r -p "Do you want to install the Nvidia drivers and dependencies? (y/N): " install_nvidia
if [[ ! "$install_nvidia" =~ ^[Yy]$ ]]; then
  echo "Skipping Nvidia driver installation."
  exit 0
fi

info "Installing build dependencies..."
dnf_install kernel-devel kernel-headers gcc make dkms acpid \
  libglvnd-glx libglvnd-opengl libglvnd-devel pkgconfig

info "Adding RPM Fusion repositories..."
FEDORA_VER="$(rpm -E %fedora)"
dnf_install \
  "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
  "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"
sudo dnf makecache

info "Installing Nvidia driver (580xx)..."
dnf_install akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx xorg-x11-drv-nvidia-580xx-cuda

info "Building kernel modules and updating initramfs..."
sudo akmods --force
sudo dracut --force

ok "Nvidia drivers installed."
