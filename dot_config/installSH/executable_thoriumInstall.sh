#!/usr/bin/env bash
set -euo pipefail

# Get the latest release info from GitHub API
LATEST_JSON=$(wget -qO- https://api.github.com/repos/Alex313031/thorium/releases/latest)

# Extract the first AVX2 .deb asset URL
DOWNLOAD_URL=$(echo "$LATEST_JSON" | grep "browser_.*AVX2.rpm" | grep "browser_download_url" \
  | head -n1 | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
  echo "❌ Could not find an AVX2 .rpm package in the latest release."
  exit 1
fi

echo "➡️ Downloading Thorium from:"
echo "$DOWNLOAD_URL"

# Save it as /tmp/thorium-avx2.deb
wget -O /tmp/thorium-avx2.rpm "$DOWNLOAD_URL"

# Install it
sudo dnf install /tmp/thorium-avx2.rpm

echo "✅ Thorium installed successfully!"
