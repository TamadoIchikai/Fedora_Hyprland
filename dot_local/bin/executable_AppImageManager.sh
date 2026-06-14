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

# ---- USAGE ----
print_usage() {
  echo "Usage:"
  echo "  AppImageManager.sh install --dir <AppImage file path>: Install chosen AppImage file"
  echo "  AppImageManager.sh delete: Open zenity to delete an installed AppImage"
}

if (($# == 0)); then
  print_usage
  exit 1
fi

MODE="$1"
shift

# ---- DELETE HELPER FUNCTION ----
select_app() {
  mapfile -t APPS < <(find -L "$APP_DIR" -maxdepth 1 -type f -iname "*.AppImage" -printf "%f\n" | sort)

  if ((${#APPS[@]} == 0)); then
    echo "No AppImages found in $APP_DIR" >&2
    exit 1
  fi

  if $HAS_ZENITY; then
    # GTK warnings are explicitly NOT silenced here
    zenity --list \
      --title="Select AppImage to remove" \
      --column="AppImage" \
      "${APPS[@]}" \
      --height=400 --width=500
  else
    echo "Select AppImage to remove:" >&2
    select opt in "${APPS[@]}"; do
      echo "${opt:-}"
      break
    done
  fi
}

case "$MODE" in
  install)
    # ---- INSTALL MODE ----
    APPIMAGE_PATH=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --dir)
          APPIMAGE_PATH="$2"
          shift 2
          ;;
        *)
          echo "Error: Unknown option $1 for install" >&2
          print_usage
          exit 1
          ;;
      esac
    done

    if [[ -z "$APPIMAGE_PATH" ]]; then
      echo "Error: install mode requires --dir <AppImage file path>" >&2
      print_usage
      exit 1
    fi

    APPIMAGE_PATH="$(realpath -- "$APPIMAGE_PATH")"

    if [[ ! -f "$APPIMAGE_PATH" ]]; then
      echo "Error: file not found: $APPIMAGE_PATH" >&2
      exit 1
    fi

    if [[ "${APPIMAGE_PATH,,}" != *.appimage ]]; then
      echo "Error: not an .AppImage file: $APPIMAGE_PATH" >&2
      exit 1
    fi

    APP_NAME_ORIG="$(basename -- "$APPIMAGE_PATH")"
    APP_NAME_ORIG="${APP_NAME_ORIG%.*}"
    
    # Enforce lowercase for file saving
    APP_NAME_LOWER="${APP_NAME_ORIG,,}"

    APPIMAGE_DEST="$APP_DIR/$APP_NAME_LOWER.AppImage"
    DESKTOP_FILE="$DESKTOP_DIR/$APP_NAME_LOWER.desktop"

    echo "Processing: $APP_NAME_ORIG (Saving as $APP_NAME_LOWER)"

    # Copy & Permissions
    cp -f -- "$APPIMAGE_PATH" "$APPIMAGE_DEST"
    chmod +x -- "$APPIMAGE_DEST"

    # Extract Icon
    TMP_DIR="$(mktemp -d)"
    cleanup() { rm -rf -- "$TMP_DIR"; }
    trap cleanup EXIT

    ICON_DEST=""

    {
      cd "$TMP_DIR"
      if "$APPIMAGE_DEST" --appimage-extract >/dev/null 2>&1; then
        ICON_PATH="$(find squashfs-root -type f \( -iname "*.png" -o -iname "*.svg" \) 2>/dev/null | awk '
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
            }' | sort -nr | head -n 1 | cut -f2-)"

        if [[ -n "${ICON_PATH:-}" && -f "$ICON_PATH" ]]; then
          EXT="${ICON_PATH##*.}"
          ICON_DEST="$ICON_DIR/$APP_NAME_LOWER.$EXT"
          cp -f -- "$ICON_PATH" "$ICON_DEST"
          echo "Icon extracted: $ICON_DEST"
        fi
      else
        echo "Warning: AppImage extraction failed. Proceeding with fallback icon."
      fi
    } || true

    if [[ -z "$ICON_DEST" ]]; then
      ICON_DEST="$ICON_DIR/$APP_NAME_LOWER.png"
      if [[ -f /usr/share/pixmaps/gnome-application-x-executable.png ]]; then
        cp -f -- /usr/share/pixmaps/gnome-application-x-executable.png "$ICON_DEST" || true
        echo "No icon found in AppImage; using fallback: $ICON_DEST"
      else
        echo "No icon found and no fallback icon available; continuing without icon copy." >&2
      fi
    fi

    # Create Desktop File
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME_ORIG
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

    MSG="$APP_NAME_ORIG installed successfully"
    echo "$MSG"
    echo "AppImage: $APPIMAGE_DEST"
    echo "Desktop file: $DESKTOP_FILE"
    echo "Icon: $ICON_DEST"

    if $HAS_NOTIFY; then
      notify-send "AppImage Installed" "$APP_NAME_ORIG is ready in your launcher" || true
    fi
    ;;

  delete)
    # ---- DELETE MODE ----
    if (($# > 0)); then
      FILE="$1"
    else
      FILE="$(select_app)" || exit 1
    fi
    
    if [[ -z "$FILE" ]]; then
      echo "No AppImage selected. Exiting."
      exit 0
    fi

    BASENAME="$(basename -- "$FILE")"
    APP_NAME_RAW="$BASENAME"
    APP_NAME_RAW="${APP_NAME_RAW%.AppImage}"
    APP_NAME_RAW="${APP_NAME_RAW%.appimage}"
    APP_NAME_RAW="${APP_NAME_RAW%.desktop}"

    # Determine both exact and lowercase variants to ensure thorough cleanup
    APP_NAME_EXACT="$APP_NAME_RAW"
    APP_NAME_LOWER="${APP_NAME_RAW,,}"

    TARGET_NAMES=("$APP_NAME_EXACT")
    if [[ "$APP_NAME_EXACT" != "$APP_NAME_LOWER" ]]; then
      TARGET_NAMES+=("$APP_NAME_LOWER")
    fi

    REMOVED=false

    for N in "${TARGET_NAMES[@]}"; do
      APPIMAGE_PATH="$APP_DIR/$N.AppImage"
      DESKTOP_FILE="$DESKTOP_DIR/$N.desktop"

      # 1. Attempt to remove Desktop file FIRST
      if [[ -f "$DESKTOP_FILE" || -L "$DESKTOP_FILE" ]]; then
        if rm -- "$DESKTOP_FILE"; then
          echo "Removed desktop file: $DESKTOP_FILE"
          REMOVED=true
        else
          MSG="Failed to remove .desktop file: $DESKTOP_FILE"
          echo "Error: $MSG" >&2
          if $HAS_NOTIFY; then
            notify-send --urgency=critical "AppImage Removal Error" "$MSG" || true
          fi
          exit 1
        fi
      fi

      # 2. Attempt to remove AppImage SECOND (Only executes if Desktop removal succeeded or didn't exist)
      if [[ -f "$APPIMAGE_PATH" || -L "$APPIMAGE_PATH" ]]; then
        if rm -- "$APPIMAGE_PATH"; then
          echo "Removed AppImage: $APPIMAGE_PATH"
          REMOVED=true
        else
          MSG="Failed to remove AppImage binary: $APPIMAGE_PATH"
          echo "Error: $MSG" >&2
          if $HAS_NOTIFY; then
            notify-send --urgency=critical "AppImage Removal Error" "$MSG" || true
          fi
          exit 1
        fi
      fi

      # 3. Attempt to remove Icons LAST (Only executes if previous steps succeeded)
      shopt -s nullglob
      for icon in "$ICON_DIR/$N".*; do
        [[ -f "$icon" || -L "$icon" ]] || continue
        if rm -- "$icon"; then
          echo "Removed icon: $icon"
          REMOVED=true
        else
          MSG="Failed to remove icon file: $icon"
          echo "Error: $MSG" >&2
          if $HAS_NOTIFY; then
            notify-send --urgency=critical "AppImage Removal Error" "$MSG" || true
          fi
          exit 1
        fi
      done
      shopt -u nullglob
    done

    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
    fi

    # Final Success Output
    if $REMOVED; then
      MSG="$APP_NAME_RAW removed successfully"
      echo "$MSG"
      if $HAS_NOTIFY; then
        notify-send "AppImage Removed" "$MSG" || true
      fi
    else
      MSG="Nothing found to remove for $APP_NAME_RAW"
      echo "$MSG"
      if $HAS_NOTIFY; then
        notify-send "AppImage Removal" "$MSG" || true
      fi
    fi
    ;;

  *)
    # ---- UNKNOWN MODE ----
    echo "Error: Unknown command '$MODE'" >&2
    print_usage
    exit 1
    ;;
esac
