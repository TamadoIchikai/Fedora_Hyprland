#!/usr/bin/env bash
set -euo pipefail

# ---- CONFIG ----
REPO="imputnet/helium-linux"
ASSET_PATTERN="x86_64.AppImage"

INSTALL_DIR="$HOME/Downloads/Systems/helium/"
APP_NAME="Helium"
APPIMAGE_PATH="$INSTALL_DIR/${APP_NAME}.AppImage"

BINARY_DIR="$HOME/.local/bin"
APPIMAGE_BIN="$BINARY_DIR/${APP_NAME}.AppImage"

DESKTOP_DIR="${DESKTOP_DIR:-$HOME/.local/share/applications}"
ICON_DIR="${ICON_DIR:-$HOME/.local/share/icons}"

# ---- CREATE DIRECTORIES ----
mkdir -p "$INSTALL_DIR" "$BINARY_DIR" "$DESKTOP_DIR" "$ICON_DIR"

# ---- CHECK DEPENDENCIES ----
HAS_NOTIFY=false
command -v notify-send >/dev/null 2>&1 && HAS_NOTIFY=true

# ---- FETCH DOWNLOAD URL ----
echo "➡️ Fetching latest Helium release..."

DOWNLOAD_URL=$(wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" \
  | jq -r ".assets[] 
    | select(.name | test(\"${ASSET_PATTERN}\")) 
    | .browser_download_url" \
  | head -n 1)

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
  echo "❌ Could not find x86_64 AppImage in the latest release."
  exit 1
fi

echo "➡️ Downloading from:"
echo "$DOWNLOAD_URL"

# ---- PREPARE INSTALL DIR ----
echo "➡️ Preparing install directory..."

if [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
  echo "➡️ Cleaning existing files in $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR"/*
fi

# ---- DOWNLOAD ----
echo "➡️ Downloading AppImage..."
wget -O "$APPIMAGE_PATH" "$DOWNLOAD_URL"

# ---- MAKE EXECUTABLE & COPY ----
chmod +x "$APPIMAGE_PATH"

echo "➡️ Copying to ~/.local/bin..."
cp -f "$APPIMAGE_PATH" "$APPIMAGE_BIN"
chmod +x "$APPIMAGE_BIN"

# ---- EXTRACT ICON ----
echo "➡️ Extracting icon..."
TMP_DIR="$(mktemp -d)"
ICON_DEST=""

(
  cd "$TMP_DIR"
  "$APPIMAGE_BIN" --appimage-extract >/dev/null 2>&1 || true

  ICON_PATH="$(
    find squashfs-root -type f \( -iname "*.png" -o -iname "*.svg" \) 2>/dev/null \
    | sort \
    | head -n 1
  )"

  if [[ -n "${ICON_PATH:-}" && -f "$ICON_PATH" ]]; then
    EXT="${ICON_PATH##*.}"
    ICON_DEST="$ICON_DIR/helium.$EXT"
    cp -f "$ICON_PATH" "$ICON_DEST"
  fi
)

rm -rf "$TMP_DIR"

# ---- FALLBACK ICON ----
if [[ -z "$ICON_DEST" ]]; then
  ICON_DEST="$ICON_DIR/helium.png"
  cp -f /usr/share/pixmaps/gnome-application-x-executable.png "$ICON_DEST" 2>/dev/null || true
fi

# ---- DESKTOP FILE ----
DESKTOP_FILE="$DESKTOP_DIR/helium.desktop"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Helium
Comment=Minimal Chromium-based browser
Exec="$APPIMAGE_BIN" %u
TryExec=$APPIMAGE_BIN
Icon=$ICON_DEST
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
Keywords=browser;web;helium;
EOF

chmod +x "$DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

# ---- DONE ----
echo ""
echo "✅ Helium installed successfully!"
echo "📁 $INSTALL_DIR"
echo "🚀 $APPIMAGE_BIN"

if $HAS_NOTIFY; then
  notify-send "Helium Installed" "Helium browser is ready" || true
fi
