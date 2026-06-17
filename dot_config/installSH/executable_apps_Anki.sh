#!/usr/bin/env bash
set -euo pipefail

# ---- CONFIGURATION ----
INSTALL_DIR="$HOME/Downloads/Studies/Anki"
TMP_DIR="$(mktemp -d /tmp/anki_installer.XXXXXX)"

# Bulletproof cleanup function
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
for cmd in curl jq tar zstd sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Error: '$cmd' is required but not installed." >&2
        exit 1
    fi
done

echo "========================================"
echo "Processing Anki..."
echo "========================================"

# 1. Fetch Latest Release URL (Filtering for the new anki-launcher format)
echo "🔍 Finding latest release..."
REPO="ankitects/anki"
PATTERN="anki-launcher-.*-linux\\.tar\\.zst$"

# Notice the URL is now just /releases (not /releases/latest)
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/${REPO}/releases" | \
               jq -r --arg pat "$PATTERN" '.[].assets[]? | select(.name | test($pat; "i")) | .browser_download_url' | head -n 1)

if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
    echo "❌ Error: Could not find Anki download URL." >&2
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
tar --zstd -xf "$TMP_DOWNLOAD_PATH" -C "$INSTALL_DIR" --strip-components=1

# 4.5 Fix Python version requirement in pyproject.toml
echo "🔧 Patching pyproject.toml requires-python to >=3.10..."
sed -i 's/>=3.9/>=3.10/g' "$INSTALL_DIR/pyproject.toml"

# 5. Patch Install & Uninstall Scripts for Local User installation
echo "🔧 Patching Anki scripts to use ~/.local instead of /usr/local..."
sed -i "s|PREFIX=/usr/local|PREFIX=$HOME/.local|g" "$INSTALL_DIR/install.sh" "$INSTALL_DIR/uninstall.sh"

# 6. Execute Local Installation
echo "🚀 Running Anki installer..."
pushd "$INSTALL_DIR" >/dev/null || exit 1
./install.sh
popd >/dev/null || exit 1

echo ""
echo "🎉 Anki installation is completely automated and finished!"
echo "   It is now registered in your application launcher."
echo "   (Note: The very first time you launch it, it will take a moment to download system dependencies.)"
