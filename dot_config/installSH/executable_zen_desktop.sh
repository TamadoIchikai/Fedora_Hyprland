#!/usr/bin/env bash
set -euo pipefail

DESKTOP_FILE="$HOME/.local/share/applications/zen.desktop"

BIN_PATH="/home/ichikai/Downloads/Systems/zen/zen"
ICON_PATH="/home/ichikai/Downloads/Systems/zen/browser/chrome/icons/default/default64.png"

echo "➡️ Creating desktop entry at: $DESKTOP_FILE"

mkdir -p "$(dirname "$DESKTOP_FILE")"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Zen Browser
Comment=Zen browser
Exec=$BIN_PATH %U
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
Icon=$ICON_PATH
EOF

chmod 644 "$DESKTOP_FILE"
chmod +x "$DESKTOP_FILE" || true

echo "✅ Desktop entry created!"
echo "You can now launch Zen Browser from your application menu."

echo "✅ Zen Browser is now executable everywhere using the command: zen"
echo "✅ Installation complete!"
