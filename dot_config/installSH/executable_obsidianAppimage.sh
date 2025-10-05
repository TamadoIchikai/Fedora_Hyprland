#!/usr/bin/env bash
set -euo pipefail

# Directory to save the AppImage
DEST_DIR="$HOME/Downloads/tmp"
mkdir -p "$DEST_DIR"

# GitHub repo for Obsidian releases
REPO="obsidianmd/obsidian-releases"

echo "Fetching latest release info from GitHub..."
# Use GitHub API to get latest release JSON
release_json=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")

# From the JSON, extract the asset URL that ends with ".AppImage" (not arm64, unless you want that)
# You might need to adjust filters if multiple archs are present.
appimage_url=$(echo "$release_json" | grep "browser_download_url" | grep -E "\.AppImage\"" | grep -v "arm64" | cut -d '"' -f 4 | head -n1)

if [[ -z "$appimage_url" ]]; then
  echo "Error: Could not find a .AppImage asset in the latest release."
  exit 1
fi

echo "Found AppImage URL: $appimage_url"

# Determine filename from URL
filename=$(basename "$appimage_url")

# Full path
dest_path="$DEST_DIR/$filename"

echo "Downloading to $dest_path ..."
curl -L --progress-bar "$appimage_url" -o "$dest_path"

echo "Making the AppImage executable..."
chmod +x "$dest_path"

echo "Done. AppImage saved at: $dest_path"
