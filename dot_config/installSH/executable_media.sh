#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -e
echo -e "${BLUE}-------> Install image and video related things${NC}"
sudo dnf install swayimg slurp wl-clipboard grim wtype swappy vlc ImageMagick hyprpicker
echo -e "${GREEN}-------> DONE${NC}"
