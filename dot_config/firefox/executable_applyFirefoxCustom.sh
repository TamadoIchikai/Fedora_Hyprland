#!/bin/bash
# firefox-chrome-setup.sh
# 1. Copy chrome/ + user.js into default-release profile
# 2. Copy config-prefs.js + config.js into system Firefox install

# ---------------------------
# Part 1: Profile customization
# ---------------------------
PROFILE_DIR="$HOME/.mozilla/firefox"

# Find profile ending in .default-release
PROFILE=$(find "$PROFILE_DIR" -maxdepth 1 -type d -name "*.default-release" | head -n 1)

if [ -z "$PROFILE" ]; then
    echo "❌ No .default-release profile found in $PROFILE_DIR"
    exit 1
fi

echo "✅ Found Firefox profile: $PROFILE"

# Copy chrome folder
SRC_CHROME="$HOME/.config/firefox/chrome"
DEST_CHROME="$PROFILE/chrome"

if [ -d "$SRC_CHROME" ]; then
    echo "📂 Copying $SRC_CHROME → $DEST_CHROME"
    rm -rf "$DEST_CHROME"
    cp -r "$SRC_CHROME" "$DEST_CHROME"
else
    echo "⚠️ chrome folder not found: $SRC_CHROME (skipping)"
fi

# Copy user.js
SRC_USERJS="$HOME/.config/firefox/config/user.js"
DEST_USERJS="$PROFILE/user.js"

if [ -f "$SRC_USERJS" ]; then
    echo "📝 Copying $SRC_USERJS → $DEST_USERJS"
    cp "$SRC_USERJS" "$DEST_USERJS"
else
    echo "⚠️ user.js not found: $SRC_USERJS (skipping)"
fi

# ---------------------------
# Part 2: System-wide config
# ---------------------------

# Locate firefox binary
FIREFOX_BIN=$(command -v firefox || true)
if [ -z "$FIREFOX_BIN" ]; then
    echo "❌ Firefox binary not found in PATH, please install via package manager"
    exit 1
fi

# Detect firefox install dir
if [ -d "/usr/lib/firefox" ]; then
    FIREFOX_DIR="/usr/lib/firefox"
    echo "✅ Found Firefox in /usr/lib/firefox"
elif [ -d "/usr/lib64/firefox" ]; then
    FIREFOX_DIR="/usr/lib64/firefox"
    echo "✅ Found Firefox in /usr/lib64/firefox"
else
    echo "❌ Could not locate Firefox system directory (/usr/lib or /usr/lib64)"
    exit 1
fi


# Expected config dirs
PREFS_DIR="$FIREFOX_DIR/defaults/pref"

SRC_PREFS="$HOME/.config/firefox/config/config-prefs.js"
SRC_CONFIG="$HOME/.config/firefox/config/config.js"

if [ -f "$SRC_PREFS" ]; then
    echo "⚙️  Copying $SRC_PREFS → $PREFS_DIR/"
    sudo mkdir -p "$PREFS_DIR"
    sudo cp "$SRC_PREFS" "$PREFS_DIR/"
else
    echo "⚠️ config-prefs.js not found: $SRC_PREFS (skipping)"
fi

if [ -f "$SRC_CONFIG" ]; then
    echo "⚙️  Copying $SRC_CONFIG → $FIREFOX_DIR/"
    sudo cp "$SRC_CONFIG" "$FIREFOX_DIR/"
else
    echo "⚠️ config.js not found: $SRC_CONFIG (skipping)"
fi

echo "🎉 Done! Restart Firefox to apply changes."
