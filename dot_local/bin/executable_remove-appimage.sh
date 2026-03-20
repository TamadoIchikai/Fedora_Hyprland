#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/.local/bin}"
DESKTOP_DIR="${DESKTOP_DIR:-$HOME/.local/share/applications}"
ICON_DIR="${ICON_DIR:-$HOME/.local/share/icons}"

HAS_NOTIFY=false
command -v notify-send >/dev/null 2>&1 && HAS_NOTIFY=true

HAS_ZENITY=false
command -v zenity >/dev/null 2>&1 && HAS_ZENITY=true

select_app() {
  mapfile -t APPS < <(find "$APP_DIR" -maxdepth 1 -type f -name "*.AppImage" -printf "%f\n" | sort)

  if ((${#APPS[@]} == 0)); then
    echo "No AppImages found in $APP_DIR" >&2
    exit 1
  fi

  if $HAS_ZENITY; then
    zenity --list \
      --title="Select AppImage to remove" \
      --column="AppImage" \
      "${APPS[@]}" \
      --height=400 --width=500
  else
    echo "Select AppImage to remove:"
    select opt in "${APPS[@]}"; do
      echo "${opt:-}"
      break
    done
  fi
}

# ---- INPUT ----
if (($# == 0)); then
  FILE="$(select_app)" || exit 1
else
  FILE="$1"
fi

# ---- NORMALIZE NAME ----
BASENAME="$(basename -- "$FILE")"
APP_NAME="$BASENAME"
APP_NAME="${APP_NAME%.AppImage}"
APP_NAME="${APP_NAME%.desktop}"

APPIMAGE_PATH="$APP_DIR/$APP_NAME.AppImage"
DESKTOP_FILE="$DESKTOP_DIR/$APP_NAME.desktop"

REMOVED=false

if [[ -f "$APPIMAGE_PATH" ]]; then
  rm -f -- "$APPIMAGE_PATH"
  echo "Removed AppImage: $APPIMAGE_PATH"
  REMOVED=true
fi

if [[ -f "$DESKTOP_FILE" ]]; then
  rm -f -- "$DESKTOP_FILE"
  echo "Removed desktop file: $DESKTOP_FILE"
  REMOVED=true
fi

# Avoid literal glob when nothing matches
shopt -s nullglob
for icon in "$ICON_DIR/$APP_NAME".*; do
  [[ -f "$icon" ]] || continue
  rm -f -- "$icon"
  echo "Removed icon: $icon"
  REMOVED=true
done
shopt -u nullglob

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

if $REMOVED; then
  MSG="$APP_NAME removed successfully"
else
  MSG="Nothing found for $APP_NAME"
fi

echo "$MSG"

if $HAS_NOTIFY; then
  notify-send "AppImage Removed" "$MSG" || true
fi