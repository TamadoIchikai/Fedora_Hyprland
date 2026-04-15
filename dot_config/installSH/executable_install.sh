#!/usr/bin/env bash
set -euo pipefail

# Dynamically get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Export colors so child scripts can use them without redefining
export BLUE='\033[0;34m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export NC='\033[0m'

echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}   Starting Hyprland Setup & Install...   ${NC}"
echo -e "${BLUE}==========================================${NC}"

# Create base directories
mkdir -p ~/Downloads/Systems/tmp ~/.local/bin/ ~/.local/share/fonts/ ~/.local/share/applications/

# Helper function to run scripts safely
run_step() {
    local desc=$1
    local script_name=$2
    local script_path="$SCRIPT_DIR/$script_name"

    echo -e "\n${BLUE}------------> $desc ${NC}"
    
    if [[ -f "$script_path" ]]; then
        chmod +x "$script_path"
        "$script_path" || { echo -e "${YELLOW}✖ Failed at step: $desc${NC}"; exit 1; }
    else
        echo -e "${YELLOW}✖ Script not found: $script_name${NC}"
        exit 1
    fi
}

# --- 1. Hardware & System Base ---
run_step "WiFi & Nvidia Drivers" "wifi_nvidia.sh"
run_step "Core Packages (Hyprland)" "core.sh"

# --- 2. Fonts, Theming & UI ---
run_step "Fonts & Icons" "fonts.sh"
run_step "File Manager (Thunar & Config)" "file_manager.sh"
run_step "Keyboard Layout (Fcitx5)" "fcitx.sh"
run_step "Waybar & Networking" "waybar.sh"

# --- 3. Base Utilities ---
run_step "Media Tools (Images/Video)" "media.sh"
run_step "Display Mode Switcher" "hyprmode/install.sh"
run_step "Battery Threshold (TLP)" "tlp_change.sh"
run_step "Cloudflare WARP" "cloudflare.sh"

# --- 4. Extra Applications ---
run_step "CLI Tools" "apps_CLI.sh"
run_step "VSCode" "apps_vscode.sh"
run_step "Mailspring" "apps_mailspring.sh"
run_step "OpenTabletDriver" "apps_opentablet.sh"
run_step "Sioyek PDF Viewer (AppImages)" "apps_sioyek.sh"
run_step "LocalSend (AppImages)" "apps_localsend.sh"
run_step "Obsidian (AppImages)" "apps_localsend.sh"
run_step "Zotero (Tarball)" "apps_localsend.sh"
run_step "Helium (AppImages)" "apps_helium.sh"
run_step "Flatpak stuffs and Extras" "apps_extra.sh"

echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}-------> ALL INSTALLATION STEPS COMPLETED!${NC}"
echo -e "${GREEN}==========================================${NC}"
