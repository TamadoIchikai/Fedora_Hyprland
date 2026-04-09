#!/usr/bin/env bash
set -euo pipefail

echo -e "${BLUE}-------> Install VPN 1.1.1.1 (Cloudflare WARP)${NC}"

curl -fsSl https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | sudo tee /etc/yum.repos.d/cloudflare-warp.repo
sudo dnf update -y
sudo dnf install -y cloudflare-warp

echo -e "${GREEN}-------> DONE${NC}"