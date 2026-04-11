#!/usr/bin/env bash
set -euo pipefail

# ---- CONFIG ----
INSTALL_DIR="$HOME/Downloads/Studies/Obsidian"
APPIMAGE_PATH="$INSTALL_DIR/Obsidian.AppImage"

BINARY_DIR="$HOME/.local/bin"
APPIMAGE_BIN="$BINARY_DIR/Obsidian.AppImage"

DESKTOP_DIR="${DESKTOP_DIR:-$HOME/.local/share/applications}"
ICON_DIR="${ICON_DIR:-$HOME/.local/share/icons}"

DOWNLOAD_URL="https://github.com/obsidianmd/obsidian-releases/releases/latest/download/Obsidian-*.AppImage"

# ---- CREATE DIRECTORIES ----
mkdir -p "$INSTALL_DIR" "$BINARY_DIR" "$DESKTOP_DIR" "$ICON_DIR"

echo "=== Obsidian AppImage Installer ==="

# ---- CLEAN INSTALL DIR (no -rf) ----
if [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
  echo "[+] Cleaning existing files..."
  find "$INSTALL_DIR" -mindepth 1 -exec rm -r {} +
fi

# ---- DOWNLOAD ----
echo "[+] Fetching latest Obsidian release..."

DOWNLOAD_URL=$(curl -s https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest \
  | grep "browser_download_url" \
  | grep "AppImage" \
  | grep -v "arm64" \
  | cut -d '"' -f 4 \
  | head -n 1)

if [[ -z "${DOWNLOAD_URL}" ]]; then
  echo "[-] Could not find AppImage download URL"
  exit 1
fi

echo "[+] Downloading from:"
echo "$DOWNLOAD_URL"

TMP_FILE="$(mktemp /tmp/obsidian-XXXXXX.AppImage)"

if ! curl --fail --show-error -L "$DOWNLOAD_URL" -o "$TMP_FILE"; then
  echo "[-] Download failed"
  exit 1
fi

if [[ ! -s "$TMP_FILE" ]]; then
  echo "[-] Downloaded file is empty"
  rm "$TMP_FILE" 2>/dev/null || true
  exit 1
fi
# ---- MOVE INTO INSTALL DIR ----
mv "$TMP_FILE" "$APPIMAGE_PATH"
chmod +x "$APPIMAGE_PATH"

# ---- COPY TO ~/.local/bin ----
echo "[+] Installing binary..."
cp -f "$APPIMAGE_PATH" "$APPIMAGE_BIN"
chmod +x "$APPIMAGE_BIN"

# ---- ICON (simple approach) ----
ICON_DEST="$ICON_DIR/obsidian.png"

echo "[+] Extracting icon..."
TMP_DIR="$(mktemp -d)"

(
  cd "$TMP_DIR"

  # Try extraction (ignore failure)
  "$APPIMAGE_BIN" --appimage-extract >/dev/null 2>&1 || true

  # Only proceed if extraction actually worked
  if [[ -d "squashfs-root" ]]; then
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
      ICON_DEST="$ICON_DIR/obsidian.$EXT"
      cp -f -- "$ICON_PATH" "$ICON_DEST"
      echo "[+] Icon extracted: $ICON_DEST"
    fi
  else
    echo "[!] AppImage extraction did not produce squashfs-root"
  fi
)

# cleanup (no -rf)
rm -r "$TMP_DIR" 2>/dev/null || true

# ---- DESKTOP ENTRY ----
echo "[+] Creating desktop entry..."

DESKTOP_FILE="$DESKTOP_DIR/obsidian.desktop"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Obsidian
Exec=$APPIMAGE_BIN %u
TryExec=$APPIMAGE_BIN
Icon=$ICON_DEST
Terminal=false
Categories=Office;Utility;
StartupNotify=true
EOF

chmod +x "$DESKTOP_FILE"

# ---- UPDATE DB ----
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

echo ""
echo "[✓] Obsidian installed successfully!"
echo "    Location: $INSTALL_DIR"
echo "    Binary:   $APPIMAGE_BIN"
