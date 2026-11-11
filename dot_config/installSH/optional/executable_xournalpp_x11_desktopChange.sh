#!/usr/bin/env bash
set -euo pipefail

SYSTEM_DESKTOP="/usr/share/applications/com.github.xournalpp.xournalpp.desktop"
USER_DESKTOP="$HOME/.local/share/applications/com.github.xournalpp.xournalpp.desktop"

echo "➡️ Preparing Xournal++ launcher override..."

# Create user applications directory

mkdir -p "$HOME/.local/share/applications"

# Copy system desktop file

cp "$SYSTEM_DESKTOP" "$USER_DESKTOP"

echo "➡️ Forcing X11 backend for Xournal++..."

# Replace Exec line

sed -i 's|^Exec=.*|Exec=env GDK_BACKEND=x11 xournalpp-wrapper %f|' "$USER_DESKTOP"

echo "✅ Xournal++ desktop launcher configured:"
echo "$USER_DESKTOP"

