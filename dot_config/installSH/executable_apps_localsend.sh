#!/usr/bin/env bash
set -euo pipefail

# ---- CONFIG ----
REPO="localsend/localsend"
ASSET_SUFFIX="linux-x86-64.AppImage"
INSTALL_DIR="$HOME/Downloads/Systems/localsend/"
APPIMAGE_PATH="$INSTALL_DIR/LocalSend.AppImage"
BINARY_DIR="$HOME/.local/bin"
APPIMAGE_BIN="$BINARY_DIR/LocalSend.AppImage"
DESKTOP_DIR="${DESKTOP_DIR:-$HOME/.local/share/applications}"
ICON_DIR="${ICON_DIR:-$HOME/.local/share/icons}"

# ---- CREATE DIRECTORIES ----
mkdir -p "$INSTALL_DIR" "$BINARY_DIR" "$DESKTOP_DIR" "$ICON_DIR"

# ---- CHECK DEPENDENCIES ----
HAS_NOTIFY=false
command -v notify-send >/dev/null 2>&1 && HAS_NOTIFY=true

# ---- FETCH DOWNLOAD URL ----
echo "➡️ Fetching latest LocalSend release..."

DOWNLOAD_URL=$(wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" \
  | jq -r ".assets[] | select(.name | endswith(\"${ASSET_SUFFIX}\")) | .browser_download_url" | head -n 1)

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
  echo "❌ Could not find Linux AppImage in the latest release."
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

# ---- DOWNLOAD DIRECTLY ----
echo "➡️ Downloading AppImage to $INSTALL_DIR..."
wget -O "$APPIMAGE_PATH" "$DOWNLOAD_URL"

# ---- MAKE EXECUTABLE & COPY TO BIN ----
echo "➡️ Setting executable permission on original file..."
chmod +x "$APPIMAGE_PATH"

echo "➡️ Copying AppImage to ~/.local/bin..."
cp -f "$APPIMAGE_PATH" "$APPIMAGE_BIN"
chmod +x "$APPIMAGE_BIN"
echo "✅ Copied to: $APPIMAGE_BIN"

# ---- EXTRACT ICON ----
echo "➡️ Extracting icon from AppImage..."
TMP_DIR="$(mktemp -d)"

ICON_DEST=""

(
  cd "$TMP_DIR"
  "$APPIMAGE_BIN" --appimage-extract >/dev/null 2>&1 || true

  ICON_PATH="$(
    find squashfs-root -type f \( -iname "*.png" -o -iname "*.svg" \) 2>/dev/null \
    | awk '
        BEGIN { IGNORECASE=1 }
        {
          p=$0
          score=0
          if (p ~ /\.png$/) score+=1000
          if (p ~ /256/) score+=256
          else if (p ~ /128/) score+=128
          else if (p ~ /64/) score+=64
          else if (p ~ /48/) score+=48
          print score "\t" p
        }' \
    | sort -nr \
    | head -n 1 \
    | cut -f2-
  )"

  if [[ -n "${ICON_PATH:-}" && -f "$ICON_PATH" ]]; then
    EXT="${ICON_PATH##*.}"
    ICON_DEST="$ICON_DIR/localsend.$EXT"
    cp -f -- "$ICON_PATH" "$ICON_DEST"
    echo "Icon extracted: $ICON_DEST"
  fi
)

# Clean up icon extraction temp dir
rm -rf "$TMP_DIR"

# Fallback icon if none extracted
if [[ -z "$ICON_DEST" ]]; then
  ICON_DEST="$ICON_DIR/localsend.png"
  if [[ -f /usr/share/pixmaps/gnome-application-x-executable.png ]]; then
    cp -f -- /usr/share/pixmaps/gnome-application-x-executable.png "$ICON_DEST" || true
    echo "No icon found in AppImage; using fallback: $ICON_DEST"
  else
    echo "⚠️  No icon found and no fallback icon available; continuing without icon copy." >&2
  fi
fi

# ---- CREATE DESKTOP FILE ----
echo "➡️ Creating desktop file..."
DESKTOP_FILE="$DESKTOP_DIR/localsend.desktop"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=LocalSend
Comment=Share files to nearby devices
Exec="$APPIMAGE_BIN" %u
TryExec=$APPIMAGE_BIN
Icon=$ICON_DEST
Terminal=false
StartupNotify=true
Categories=Network;Utility;
Keywords=share;files;network;transfer;
EOF

chmod +x -- "$DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

# ---- DONE ----
echo ""
echo "✅ LocalSend installed successfully!"
echo "📁 Original downloaded to: $INSTALL_DIR"
echo "🚀 Executable: $APPIMAGE_BIN"
echo "📋 Desktop file: $DESKTOP_FILE"
echo "🎨 Icon: $ICON_DEST"

if $HAS_NOTIFY; then
  notify-send "LocalSend Installed" "LocalSend is ready in your launcher" || true
fi
