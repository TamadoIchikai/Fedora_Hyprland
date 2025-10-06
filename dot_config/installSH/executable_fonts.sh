#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -e
echo -e "${BLUE}-------> Install fonts and icon${NC}"
sudo dnf install fontawesome-fonts
wget -P ~/.local/share/fonts/ -O JetBrainsMono.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip
wget -P ~/.local/share/fonts/ https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip
unzip ~/.local/share/fonts/NerdFontsSymbolsOnly.zip
unzip ~/.local/share/fonts/JetBrainsMono.zip
rm ~/.local/share/fonts/NerdFontsSymbolsOnly.zip
rm ~/.local/share/fonts/JetBrainsMono.zip
fc-cache -fv
echo -e "${GREEN}-------> Done${NC}"

