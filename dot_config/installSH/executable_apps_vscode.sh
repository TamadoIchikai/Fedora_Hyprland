#!/usr/bin/env bash
set -euo pipefail

echo -e "${BLUE}-------> Installing Visual Studio Code${NC}"

sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null

# dnf check-update returns 100 if updates are available, so we use || true to prevent script exit
dnf check-update || true
sudo dnf install -y code

echo -e "${GREEN}-------> DONE${NC}"