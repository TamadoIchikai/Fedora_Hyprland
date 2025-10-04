BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -e
echo -e "${BLUE}-------> Install core for my hyprland config ${NC}"
sudo dnf copr enable solopasha/hyprland
sudo dnf install hyprland hyprlock hyprpaper vim neovim fastfetch flatpak meson cmake
mkdir -p ~/Downloads/Systems ~/.local/bin/
