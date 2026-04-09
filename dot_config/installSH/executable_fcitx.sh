#!/usr/bin/env bash
set -euo pipefail

echo -e "${BLUE}-------> Install fcitx for Vietnamese and Japanese keyboard ${NC}"

sudo dnf install -y fcitx5 fcitx5-configtool fcitx5-unikey fcitx5-mozc

echo -e "${GREEN}-------> DONE${NC}"