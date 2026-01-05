#!/usr/bin/env bash
set -euo pipefail  # safer: stop on error, undefined var, or broken pipe

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FONT_DIR="$HOME/.local/share/fonts"
TMP_DIR="$(mktemp -d)"

echo -e "${BLUE}-------> Installing fonts and icons${NC}"

# Ensure required packages exist
if ! command -v wget &>/dev/null; then
    echo -e "${YELLOW}Installing wget...${NC}"
    sudo dnf install -y wget
fi

if ! command -v unzip &>/dev/null; then
    echo -e "${YELLOW}Installing unzip...${NC}"
    sudo dnf install -y unzip
fi

# Install Font Awesome and japanese and korean font (system-wide)
echo -e "${BLUE}Installing Font Awesome...${NC}"
sudo dnf install -y fontawesome-fonts || echo -e "${YELLOW}Font Awesome already installed or unavailable.${NC}"
sudo dnf install -y google-noto-sans-jp-fonts google-noto-serif-jp-fonts google-noto-cjk-fonts|| echo -e "${YELLOW}noto sans jp fonts and cjk already installed or unavailable.${NC}"
# Create fonts directory if missing
mkdir -p "$FONT_DIR"

# Download Nerd Fonts safely
echo -e "${BLUE}Downloading Nerd Fonts...${NC}"
wget -q -O "$TMP_DIR/JetBrainsMono.zip" "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip"
wget -q -O "$TMP_DIR/NerdFontsSymbolsOnly.zip" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip"

# Extract (overwrite quietly if already exists)
echo -e "${BLUE}Extracting fonts...${NC}"
unzip -o -qq "$TMP_DIR/JetBrainsMono.zip" -d "$FONT_DIR"
unzip -o -qq "$TMP_DIR/NerdFontsSymbolsOnly.zip" -d "$FONT_DIR"

# Clean up
rm -rf "$TMP_DIR"

# Refresh font cache
echo -e "${BLUE}Updating font cache...${NC}"
fc-cache -fv > /dev/null

echo -e "${GREEN}-------> Fonts installed successfully!${NC}"
