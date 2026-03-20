#!/usr/bin/env bash
set -euo pipefail

# ---- CONFIG ----
REPO="ahrm/sioyek"
ASSET_PATTERN="sioyek-release-linux.zip"
TMP_FILE="/tmp/sioyek-release-linux.zip"
INSTALL_DIR="$HOME/Downloads/Studies/sioyek"
DESKTOP_DIR="${DESKTOP_DIR:-$HOME/.local/share/applications}"
ICON_DIR="${ICON_DIR:-$HOME/.local/share/icons}"

# ---- CREATE DIRECTORIES ----
mkdir -p "$INSTALL_DIR" "$DESKTOP_DIR" "$ICON_DIR"

# ---- CHECK DEPENDENCIES ----
HAS_NOTIFY=false
command -v notify-send >/dev/null 2>&1 && HAS_NOTIFY=true

# ---- FETCH DOWNLOAD URL ----
echo "➡️ Fetching latest Sioyek release..."

DOWNLOAD_URL=$(wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" \
  | jq -r ".assets[] | select(.name == \"${ASSET_PATTERN}\") | .browser_download_url")

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
  echo "❌ Could not find ${ASSET_PATTERN} in latest release."
  exit 1
fi

echo "➡️ Downloading from:"
echo "$DOWNLOAD_URL"

# ---- DOWNLOAD ----
wget -O "$TMP_FILE" "$DOWNLOAD_URL"

# ---- PREPARE INSTALL DIR ----
echo "➡️ Preparing install directory..."

# Only remove if directory is NOT empty
if [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
  echo "➡️ Cleaning existing files..."
  rm -rf "$INSTALL_DIR"/*
fi

# ---- EXTRACT ----
echo "➡️ Extracting..."
unzip -o "$TMP_FILE" -d "$INSTALL_DIR"

# ---- MAKE EXECUTABLE ----
echo "➡️ Setting executable permission..."
APPIMAGE_PATH=$(find "$INSTALL_DIR" -maxdepth 1 -name "Sioyek*" -type f | head -n 1)

if [ -z "$APPIMAGE_PATH" ]; then
  echo "❌ No Sioyek executable found in $INSTALL_DIR"
  exit 1
fi

chmod +x "$APPIMAGE_PATH"
echo "✅ Made executable: $APPIMAGE_PATH"

# ---- EXTRACT ICON ----
echo "➡️ Extracting icon from AppImage..."
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf -- "$TMP_DIR"; }
trap cleanup EXIT

ICON_DEST=""

(
  cd "$TMP_DIR"
  "$APPIMAGE_PATH" --appimage-extract >/dev/null 2>&1 || true

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
    ICON_DEST="$ICON_DIR/sioyek.$EXT"
    cp -f -- "$ICON_PATH" "$ICON_DEST"
    echo "Icon extracted: $ICON_DEST"
  fi
)

# Fallback icon if none extracted
if [[ -z "$ICON_DEST" ]]; then
  ICON_DEST="$ICON_DIR/sioyek.png"
  if [[ -f /usr/share/pixmaps/gnome-application-x-executable.png ]]; then
    cp -f -- /usr/share/pixmaps/gnome-application-x-executable.png "$ICON_DEST" || true
    echo "No icon found in AppImage; using fallback: $ICON_DEST"
  else
    echo "⚠️  No icon found and no fallback icon available; continuing without icon copy." >&2
  fi
fi

# ---- CREATE DESKTOP FILE ----
echo "➡️ Creating desktop file..."
DESKTOP_FILE="$DESKTOP_DIR/sioyek.desktop"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Sioyek
Comment=PDF viewer designed for research papers
Exec="$APPIMAGE_PATH" %F
TryExec=$APPIMAGE_PATH
Icon=$ICON_DEST
Terminal=false
StartupNotify=true
Categories=Office;Utility;Application;
MimeType=application/pdf;
Keywords=pdf;viewer;
EOF

chmod +x -- "$DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

# ---- DONE ----
echo ""
echo "✅ Sioyek installed successfully!"
echo "📁 AppImage: $APPIMAGE_PATH"
echo "📋 Desktop file: $DESKTOP_FILE"
echo "🎨 Icon: $ICON_DEST"

if $HAS_NOTIFY; then
  notify-send "Sioyek Installed" "Sioyek is ready in your launcher" || true
fi
