#!/usr/bin/env bash
set -euo pipefail

FONT_DIR="$HOME/.local/share/fonts"

# Ensure required packages exist
if ! command -v wget &>/dev/null; then
    sudo dnf install -y wget
fi

if ! command -v unzip &>/dev/null; then
    sudo dnf install -y unzip
fi

# Install Font Awesome and japanese and korean font (system-wide)
sudo dnf install -y fontawesome-fonts
sudo dnf install -y google-noto-sans-jp-fonts google-noto-serif-jp-fonts google-noto-cjk-fonts 

# Create fonts directory if missing
mkdir -p "$FONT_DIR"

# --- CHECK FOR EXISTING NERD FONTS ---
NEED_JETBRAINS=true
NEED_SYMBOLS=true

# Safely check for matching font files in the directory without breaking the script if empty
shopt -s nullglob
jetbrains_files=("$FONT_DIR"/*JetBrainsMono*Nerd*.ttf)
symbols_files=("$FONT_DIR"/*SymbolsNerdFont*.ttf)
shopt -u nullglob

if ((${#jetbrains_files[@]} > 0)); then
    echo -e "JetBrainsMono Nerd Font already exists. Skipping."
    NEED_JETBRAINS=false
fi

if ((${#symbols_files[@]} > 0)); then
    echo "Nerd Fonts Symbols Only already exists. Skipping."
    NEED_SYMBOLS=false
fi

# --- DOWNLOAD AND EXTRACT (ONLY IF NEEDED) ---
if $NEED_JETBRAINS || $NEED_SYMBOLS; then
    TMP_DIR="$(mktemp -d)"
    # Ensure cleanup happens automatically upon script exit or error
    trap 'rm -rf "$TMP_DIR"' EXIT 

    if $NEED_JETBRAINS; then
        wget -q -O "$TMP_DIR/JetBrainsMono.zip" "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip"
        unzip -o -qq "$TMP_DIR/JetBrainsMono.zip" -d "$FONT_DIR"
    fi

    if $NEED_SYMBOLS; then
        wget -q -O "$TMP_DIR/NerdFontsSymbolsOnly.zip" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip"
        unzip -o -qq "$TMP_DIR/NerdFontsSymbolsOnly.zip" -d "$FONT_DIR"
    fi

    # Refresh font cache since we added new fonts
    fc-cache -fv > /dev/null
else
    echo "Nerd Fonts are installed."
fi
