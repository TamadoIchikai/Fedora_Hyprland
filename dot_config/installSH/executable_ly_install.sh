#!/usr/bin/env bash
set -e  # stop on error

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

SYSTEM_DIR="$HOME/Downloads/Systems"
ZIG_DIR="$SYSTEM_DIR/zig"
LY_DIR="$SYSTEM_DIR/ly"

echo -e "${BLUE}-------> Installing dependencies ${NC}"
sudo dnf install -y kernel-devel pam-devel libxcb-devel xorg-x11-xauth \
    xorg-x11-server-Xorg brightnessctl git wget tar

# ---------------------------------------------------------------------
# Install Zig
# ---------------------------------------------------------------------
echo -e "${BLUE}-------> Installing Zig into $ZIG_DIR ${NC}"

mkdir -p "$SYSTEM_DIR"

# Remove old Zig if exists
if [ -d "$ZIG_DIR" ]; then
    echo "Removing old Zig installation..."
    rm -rf "$ZIG_DIR"
fi

# Download and extract Zig directly
wget -q -O "$SYSTEM_DIR/zig.tar.xz" https://ziglang.org/download/0.15.1/zig-x86_64-linux-0.15.1.tar.xz
tar -xf "$SYSTEM_DIR/zig.tar.xz" -C "$SYSTEM_DIR"
mv "$SYSTEM_DIR/zig-x86_64-linux-0.15.1" "$ZIG_DIR"
rm -f "$SYSTEM_DIR/zig.tar.xz"

# Create symlink
sudo ln -sf "$ZIG_DIR/zig" /usr/local/bin/zig

echo "Zig version: $(zig version)"
echo -e "${GREEN}-------> Zig installed successfully${NC}"

# ---------------------------------------------------------------------
# Install Ly
# ---------------------------------------------------------------------
echo -e "${BLUE}-------> Cloning and building Ly into $LY_DIR ${NC}"

# Remove old Ly if exists
if [ -d "$LY_DIR" ]; then
    echo "Removing old Ly source..."
    rm -rf "$LY_DIR"
fi

git clone https://codeberg.org/fairyglade/ly.git "$LY_DIR"

# Build and install Ly
sudo zig build installexe -Dinit_system=systemd --build-file "$LY_DIR/build.zig" --mod "$LY_DIR"

# ---------------------------------------------------------------------
# Enable Ly as display manager
# ---------------------------------------------------------------------
echo -e "${BLUE}-------> Configuring Ly as systemd service ${NC}"
sudo systemctl disable getty@tty1.service || true
sudo systemctl disable getty@tty2.service || true
sudo systemctl enable ly.service
sudo systemctl set-default graphical.target

echo -e "${GREEN}-------> Ly installed and configured successfully!${NC}"
