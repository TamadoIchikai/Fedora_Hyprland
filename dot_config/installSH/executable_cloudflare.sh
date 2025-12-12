#!/bin/bash
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -euxo pipefail
echo -e "${BLUE}-------> Install VPN 1.1.1.1${NC}"
curl -fsSl https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | sudo tee /etc/yum.repos.d/cloudflare-warp.repo
sudo yum update
sudo yum install cloudflare-warp
echo -e "${GREEN}-------> DONE${NC}"
