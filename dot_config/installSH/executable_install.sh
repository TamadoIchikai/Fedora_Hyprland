#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

mkdir -p ~/Downloads/Systems/tmp ~/.local/bin/ ~/.local/share/fonts/
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
run_step "Installing vscode" ~/.config/installSH/vscode_RPM.sh
run_step "File manager" ~/.config/installSH/file_manager.sh
run_step "Media related" ~/.config/installSH/media.sh
run_step "Install waybar dependencies" ~/.config/installSH/waybar.sh
run_step "Install wifi and nvidia drivers" ~/.config/installSH/wifi_nvidia_RPM.sh
run_step "Install open tablet driver " ~/.config/installSH/opentabletdriver_RPM.sh
run_step "Cloudflare time" ~/.config/installSH/cloudflare.sh
run_step "Display mode switcher" ~/.config/installSH/hyprmode/install.sh
run_step "Battery charge threshold (TLP)" ~/.config/installSH/tlp-change.sh
run_step "sioyek installtion" ~/.config/installSH/sioyek.sh
echo -e "${GREEN}-------> DONE"
