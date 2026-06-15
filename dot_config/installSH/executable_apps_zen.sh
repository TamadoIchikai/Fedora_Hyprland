#!/usr/bin/env bash
set -euo pipefail

# ---- ROOT PRIVILEGE CHECK ----
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root to install to system directories." >&2
   echo "👉 Please run again using: sudo $0" >&2
   exit 1
fi

# ---- CONFIGURATION ----
# Standard Linux convention for third-party software is /opt/
INSTALL_DIR="/opt/zen"
TMP_DIR="$(mktemp -d /tmp/zen_installer.XXXXXX)"

# System-wide desktop shortcut and binary paths
DESKTOP_FILE="/usr/share/applications/zen.desktop"
GLOBAL_BIN="/usr/local/bin/zen"

# Dynamic paths based on your requested Install Directory
BIN_PATH="$INSTALL_DIR/zen"
ICON_PATH="$INSTALL_DIR/browser/chrome/icons/default/default64.png"

# ---- SAFETY CLEANUP ----
cleanup() {
    if [[ -z "${TMP_DIR:-}" ]]; then return; fi
    if [[ "$TMP_DIR" == /tmp/* ]]; then
        rm -rf "$TMP_DIR"
    else
        echo "⚠️ Warning: TMP_DIR ($TMP_DIR) is not in /tmp/. Skipping cleanup." >&2
    fi
}
trap cleanup EXIT

# ---- DEPENDENCY CHECK ----
for cmd in curl jq tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Error: '$cmd' is required but not installed." >&2
        exit 1
    fi
done

echo "========================================"
echo "Processing Zen Browser (System-Wide)..."
echo "========================================"

# 1. Fetch Latest Release URL
echo "🔍 Finding latest release..."
REPO="zen-browser/desktop"
PATTERN="linux-x86_64\\.tar\\.xz$"

# Query all recent releases and grab the first matching asset
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/${REPO}/releases" | \
               jq -r --arg pat "$PATTERN" '.[].assets[]? | select(.name | test($pat; "i")) | .browser_download_url' | head -n 1)

if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
    echo "❌ Error: Could not find Zen Browser download URL." >&2
    exit 1
fi

echo "🔗 Found URL: $DOWNLOAD_URL"

# 2. Download to /tmp
FILENAME=$(basename "$DOWNLOAD_URL")
TMP_DOWNLOAD_PATH="$TMP_DIR/$FILENAME"

echo "⬇️ Downloading to $TMP_DOWNLOAD_PATH..."
curl --fail --show-error -L "$DOWNLOAD_URL" -o "$TMP_DOWNLOAD_PATH"

# 3. Clean existing installation directory
mkdir -p "$INSTALL_DIR"
if [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
    echo "🗑️ Cleaning existing files in $INSTALL_DIR..."
    find "$INSTALL_DIR" -mindepth 1 -exec rm -rf {} +
fi

# 4. Extract Archive
echo "📦 Extracting to $INSTALL_DIR..."
tar -xf "$TMP_DOWNLOAD_PATH" -C "$INSTALL_DIR" --strip-components=1

# 5. Make it executable globally
echo "🔗 Linking binary to $GLOBAL_BIN..."
ln -sf "$BIN_PATH" "$GLOBAL_BIN"

# 6. Desktop Entry Integration
echo "➡️ Creating system-wide desktop entry at: $DESKTOP_FILE"
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

# Refresh system desktop database to ensure it shows up immediately
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "/usr/share/applications" >/dev/null 2>&1 || true
fi

echo "✅ Desktop entry created!"
echo "You can now launch Zen Browser from your application menu."
echo "✅ Zen Browser is now executable everywhere using the command: zen"
echo "✅ Installation complete!"
