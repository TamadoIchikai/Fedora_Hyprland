#!/usr/bin/env bash
set -euo pipefail

# ---- CONFIG ----
APP_NAME="Xournal++ Nightly"

INSTALL_DIR="$HOME/Downloads/Studies/Xournalpp"
APPIMAGE_PATH="$INSTALL_DIR/xournalpp-nightly-x86_64.AppImage"

BINARY_DIR="$HOME/.local/bin"
APPIMAGE_BIN="$BINARY_DIR/xournalpp-nightly-x86_64.AppImage"

DESKTOP_DIR="${DESKTOP_DIR:-$HOME/.local/share/applications}"
ICON_DIR="${ICON_DIR:-$HOME/.local/share/icons}"

REPO="xournalpp/xournalpp"
RELEASE_TAG="nightly"   # official nightly tag
EXTRACT_TIMEOUT_SECONDS=15

mkdir -p "$INSTALL_DIR" "$BINARY_DIR" "$DESKTOP_DIR" "$ICON_DIR"

echo "=== Xournal++ Nightly AppImage Installer ==="

# ---- CLEAN INSTALL DIR (no -rf) ----
if [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
  echo "[+] Cleaning existing files in $INSTALL_DIR ..."
  find "$INSTALL_DIR" -mindepth 1 -exec rm -r {} +
fi

# ---- FETCH ASSET URL FROM GITHUB API ----
echo "[+] Fetching nightly release asset URL..."

API_URL="https://api.github.com/repos/${REPO}/releases/tags/${RELEASE_TAG}"

if command -v jq >/dev/null 2>&1; then
  DOWNLOAD_URL="$(
    curl -fsSL "$API_URL" \
      | jq -r '
          .assets[]
          | select(.browser_download_url | test("\\.AppImage$"))
          | select(.browser_download_url | test("x86_64|amd64"; "i"))
          | select(.browser_download_url | test("zsync$") | not)
          | .browser_download_url
        ' \
      | head -n 1
  )"
else
  DOWNLOAD_URL="$(
    curl -fsSL "$API_URL" \
      | grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' \
      | cut -d '"' -f 4 \
      | grep -E '\.AppImage$' \
      | grep -Ei '(x86_64|amd64)' \
      | grep -Ev '\.zsync$' \
      | head -n 1
  )"
fi

if [[ -z "${DOWNLOAD_URL:-}" ]]; then
  echo "[-] Could not find x86_64 AppImage in ${REPO} tag '${RELEASE_TAG}'."
  echo "    https://github.com/${REPO}/releases/tag/${RELEASE_TAG}"
  exit 1
fi

echo "[+] Downloading from:"
echo "    $DOWNLOAD_URL"

TMP_FILE="$(mktemp /tmp/xournalpp-nightly-XXXXXX.AppImage)"

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
echo "[+] Installing binary to $APPIMAGE_BIN ..."
cp -f "$APPIMAGE_PATH" "$APPIMAGE_BIN"
chmod +x "$APPIMAGE_BIN"

# ---- ICON (best-effort, non-blocking) ----
ICON_DEST="$ICON_DIR/xournalpp-nightly.png"
echo "[+] Extracting icon (best-effort, timeout ${EXTRACT_TIMEOUT_SECONDS}s)..."

TMP_DIR="$(mktemp -d)"
EXTRACT_OK=0

(
  set +e
  cd "$TMP_DIR"

  # Avoid hanging forever:
  if command -v timeout >/dev/null 2>&1; then
    timeout "${EXTRACT_TIMEOUT_SECONDS}"s "$APPIMAGE_BIN" --appimage-extract >/dev/null 2>&1
    rc=$?
  else
    # No timeout available; still try but you can CTRL+C if it hangs
    "$APPIMAGE_BIN" --appimage-extract >/dev/null 2>&1
    rc=$?
  fi

  # timeout returns 124 on timeout
  if [[ $rc -eq 0 && -d "squashfs-root" ]]; then
    EXTRACT_OK=1
  fi

  if [[ $EXTRACT_OK -eq 1 ]]; then
    ICON_PATH="$(
      find squashfs-root -type f \( -iname "*.png" -o -iname "*.svg" \) 2>/dev/null \
      | awk '
          BEGIN { IGNORECASE=1 }
          {
            p=$0
            score=0
            if (p ~ /\.png$/) score+=1000
            if (p ~ /xournalpp|xournal\+\+/) score+=500
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
      ICON_DEST="$ICON_DIR/xournalpp-nightly.$EXT"
      cp -f -- "$ICON_PATH" "$ICON_DEST"
      echo "[+] Icon extracted: $ICON_DEST"
    else
      echo "[!] Extract succeeded but no icon found; using fallback icon path: $ICON_DEST"
    fi
  else
    if [[ ${rc:-0} -eq 124 ]]; then
      echo "[!] Icon extraction timed out; skipping (install continues)"
    else
      echo "[!] Icon extraction failed/unsupported; skipping (install continues)"
    fi
  fi
)

rm -r "$TMP_DIR" 2>/dev/null || true

# ---- DESKTOP ENTRY ----
echo "[+] Creating desktop entry..."
DESKTOP_FILE="$DESKTOP_DIR/xournalpp-nightly.desktop"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Exec=$APPIMAGE_BIN %u
TryExec=$APPIMAGE_BIN
Icon=$ICON_DEST
Terminal=false
Categories=Office;Utility;Graphics;
StartupNotify=true
EOF

chmod +x "$DESKTOP_FILE"

# ---- UPDATE DB ----
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

echo ""
echo "[✓] Xournal++ nightly installed successfully!"
echo "    Location: $INSTALL_DIR"
echo "    Binary:   $APPIMAGE_BIN"
echo "    Desktop:  $DESKTOP_FILE"
