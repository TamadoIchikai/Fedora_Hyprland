BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -e
echo -e "${BLUE}-------> Install fonts and icon${NC}"
sudo dnf install fontawesome-fonts
mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts
wget -O JetBrainsMono.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip
wget https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip
unzip NerdFontsSymbolsOnly.zip
unzip JetBrainsMono.zip
rm NerdFontsSymbolsOnly.zip
rm JetBrainsMono.zip
fc-cache -fv
cd
echo -e "${GREEN}-------> Done${NC}"

