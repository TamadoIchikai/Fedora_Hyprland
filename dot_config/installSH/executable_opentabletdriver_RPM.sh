#!/usr/bin/env bash
set -euo pipefail

echo "Fetching latest OpenTabletDriver .rpm release..."
latest_json=$(curl -s https://api.github.com/repos/OpenTabletDriver/OpenTabletDriver/releases/latest)
rpm_url=$(echo "$latest_json" | grep -Eo 'https://[^"]+\.x86_64\.rpm' | head -n 1)

if [[ -z "$rpm_url" ]]; then
    echo "Error: could not find any .rpm release for x86_64."
    exit 1
fi

tmpdir=$(mktemp -d /tmp/opentabletdriver.XXXXXX)
cd "$tmpdir"
rpm_file=$(basename "$rpm_url")

echo "Downloading $rpm_file..."
curl -L -o "$rpm_file" "$rpm_url"

echo "Installing via dnf..."
sudo dnf install -y "$rpm_file"

rm -rf "$tmpdir"
echo "OpenTabletDriver installed successfully."
