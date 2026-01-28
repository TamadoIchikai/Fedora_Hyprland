#!/usr/bin/env bash
set -euo pipefail

# Get the latest release info from GitHub API
LATEST_JSON=$(wget -qO- https://api.github.com/repos/Foundry376/Mailspring/releases/latest)

# Extract the .rpm asset URL
DOWNLOAD_URL=$(echo "$LATEST_JSON" | grep "browser_.*x86_64.rpm" | grep "browser_download_url" \
  | head -n1 | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
  echo "❌ Could not find an x86_64 .rpm package in the latest release."
  exit 1
fi

echo "➡️ Downloading Mailspring from:"
echo "$DOWNLOAD_URL"

# Save it as /tmp/mailspring.rpm
wget -O /tmp/mailspring.rpm "$DOWNLOAD_URL"

# Install dependencies
echo "➡️ Installing dependencies..."
sudo dnf install -y gnome-keyring gnome-keyring-pam seahorse

# Install Mailspring
echo "➡️ Installing Mailspring..."
sudo dnf install -y /tmp/mailspring.rpm

# Modify the desktop file to add flags
DESKTOP_FILE="/usr/share/applications/Mailspring.desktop"
if [ -f "$DESKTOP_FILE" ]; then
  echo "➡️ Configuring Mailspring with custom flags..."
  sudo sed -i 's|^Exec=mailspring |Exec=mailspring --password-store=gnome-libsecret --ozone-platform=x11 |' "$DESKTOP_FILE"
  sudo sed -i 's|^Exec=mailspring$|Exec=mailspring --password-store=gnome-libsecret --ozone-platform=x11|' "$DESKTOP_FILE"
  echo "✅ Desktop file updated!"
else
  echo "⚠️  Warning: Desktop file not found at $DESKTOP_FILE"
fi

echo "✅ Mailspring installed successfully!"
