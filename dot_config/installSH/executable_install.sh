#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

mkdir -p ~/Downloads/Systems/ ~/.local/bin/ ~/.local/share/fonts/
run_step() {
    desc=$1
    shift
    echo -e "${BLUE}------------> $desc ${NC}"
    "$@" || { echo -e "${GREEN}✖ Failed at step: $desc${NC}"; exit 1; }
}

run_step "core package" ~/.config/installSH/core.sh
run_step "Fonts" ~/.config/installSH/fonts.sh
run_step "keyboard layout" ~/.config/installSH/fcitx.sh
run_step "Applications" ~/.config/installSH/theBLOAT.sh
run_step "File manager" ~/.config/installSH/file_manager.sh
run_step "Media related" ~/.config/installSH/media.sh
run_step "Install waybar dependencies" ~/.config/installSH/waybar.sh
run_step "Thorium" ~/.config/installSH/thorium_install.sh
run_step "Obsidian" ~/.config/installSH/obsidianAppimage.sh

echo -e "${GREEN}------->DONE please manually start LY installation and check if network scan working correctly, if not please read README.md${NC}"

cd ~/.config/installSH/
echo -e "${GREEN}------->check and install ly_install.sh (with ly_README.md)"
