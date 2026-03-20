#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/.local/bin}"
DESKTOP_DIR="${DESKTOP_DIR:-$HOME/.local/share/applications}"
ICON_DIR="${ICON_DIR:-$HOME/.local/share/icons}"

mkdir -p "$APP_DIR" "$DESKTOP_DIR" "$ICON_DIR"

HAS_NOTIFY=false
command -v notify-send >/dev/null 2>&1 && HAS_NOTIFY=true

HAS_ZENITY=false
command -v zenity >/dev/null 2>&1 && HAS_ZENITY=true

# ---- INPUT ----
if (($# == 0)); then
  if $HAS_ZENITY; then
    APPIMAGE_PATH="$(zenity --file-selection \
      --title="Select AppImage" \
      --file-filter="*.AppImage")" || exit 1
  else
    echo "Usage: $0 /path/to/YourApp.AppImage" >&2
    exit 1
  fi
else
  APPIMAGE_PATH="$1"
fi

APPIMAGE_PATH="$(realpath -- "$APPIMAGE_PATH")"

if [[ ! -f "$APPIMAGE_PATH" ]]; then
  echo "Error: file not found: $APPIMAGE_PATH" >&2
  exit 1
fi

if [[ "${APPIMAGE_PATH##*.}" != "AppImage" ]]; then
  echo "Error: not an .AppImage file: $APPIMAGE_PATH" >&2
  exit 1
fi

APP_NAME="$(basename -- "$APPIMAGE_PATH" .AppImage)"
APPIMAGE_DEST="$APP_DIR/$APP_NAME.AppImage"
DESKTOP_FILE="$DESKTOP_DIR/$APP_NAME.desktop"

echo "Processing: $APP_NAME"

# ---- COPY + PERMISSION (overwrite for updates) ----
cp -f -- "$APPIMAGE_PATH" "$APPIMAGE_DEST"
chmod +x -- "$APPIMAGE_DEST"

# ---- EXTRACT ICON ----
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf -- "$TMP_DIR"; }
trap cleanup EXIT

ICON_DEST=""

(
  cd "$TMP_DIR"
  "$APPIMAGE_DEST" --appimage-extract >/dev/null 2>&1 || true

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
    ICON_DEST="$ICON_DIR/$APP_NAME.$EXT"
    cp -f -- "$ICON_PATH" "$ICON_DEST"
    echo "Icon extracted: $ICON_DEST"
  fi
)

# Fallback icon if none extracted
if [[ -z "$ICON_DEST" ]]; then
  ICON_DEST="$ICON_DIR/$APP_NAME.png"
  if [[ -f /usr/share/pixmaps/gnome-application-x-executable.png ]]; then
    cp -f -- /usr/share/pixmaps/gnome-application-x-executable.png "$ICON_DEST" || true
    echo "No icon found in AppImage; using fallback: $ICON_DEST"
  else
    echo "No icon found and no fallback icon available; continuing without icon copy." >&2
  fi
fi

# ---- CREATE DESKTOP FILE (overwrite for updates) ----
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Exec="$APPIMAGE_DEST"
TryExec=$APPIMAGE_DEST
Icon=$ICON_DEST
Terminal=false
StartupNotify=true
Categories=Utility;
EOF

chmod +x -- "$DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

MSG="$APP_NAME installed successfully"
echo "$MSG"
echo "AppImage: $APPIMAGE_DEST"
echo "Desktop file: $DESKTOP_FILE"
echo "Icon: $ICON_DEST"

if $HAS_NOTIFY; then
  notify-send "AppImage Installed" "$APP_NAME is ready in your launcher" || true
fi