#!/usr/bin/env bash
set -euo pipefail

# Extract the .rpm asset URL
DOWNLOAD_URL=$(wget -qO- https://api.github.com/repos/Foundry376/Mailspring/releases/latest \
  | jq -r '.assets[] | select(.name | test("x86_64.rpm")) | .browser_download_url' | head -n1)

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
SYSTEM_DESKTOP="/usr/share/applications/Mailspring.desktop"
USER_DESKTOP="$HOME/.local/share/applications/Mailspring.desktop"

if [ -f "$SYSTEM_DESKTOP" ]; then
  echo "➡️ Creating user desktop override..."
  mkdir -p "$HOME/.local/share/applications"
  cp "$SYSTEM_DESKTOP" "$USER_DESKTOP"
  echo "➡️ Adding custom flags..."
  sed -i \
  -e 's|^Exec=mailspring .*|Exec=mailspring --password-store=gnome-libsecret --ozone-platform=x11 %U|' \
  -e 's|^Exec=mailspring$|Exec=mailspring --password-store=gnome-libsecret --ozone-platform=x11|' \
  -e 's|^Exec=mailspring mailto:|Exec=mailspring --password-store=gnome-libsecret --ozone-platform=x11 mailto:|' \
  "$USER_DESKTOP"
  echo "✅ Desktop file updated!"
else
  echo "⚠️  Warning: Desktop file not found at $DESKTOP_FILE"
fi

echo "✅ Mailspring installed successfully!"
