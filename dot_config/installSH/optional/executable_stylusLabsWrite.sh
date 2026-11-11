#!/usr/bin/env bash
set -euo pipefail

echo "Fetching latest Stylus Labs Write .tar.gz release..."
latest_json=$(curl -s https://api.github.com/repos/styluslabs/write/releases/latest)
tar_url=$(echo "$latest_json" | grep -Eo 'https://[^"]+\.tar\.gz' | head -n 1)

if [[ -z "$tar_url" ]]; then
    echo "Error: could not find any .tar.gz release."
    exit 1
fi

destdir="$HOME/Downloads/Study"
mkdir -p "$destdir"
cd "$destdir"

tar_file=$(basename "$tar_url")

echo "Downloading $tar_file..."
curl -L -o "$tar_file" "$tar_url"

echo "Extracting $tar_file..."
tar -xvf "$tar_file"

echo "Removing archive..."
rm -f "$tar_file"

# Find the extracted Write directory
write_dir=$(find "$destdir" -type d -name "Write*" -print -quit)

if [[ -z "$write_dir" ]]; then
    echo "Error: could not locate extracted Write directory."
    exit 1
fi

cd "$write_dir"

if [[ ! -f setup.sh ]]; then
    echo "Error: setup.sh not found in $write_dir"
    exit 1
fi

echo "Running setup.sh..."
chmod +x setup.sh
./setup.sh

echo "Stylus Labs Write installed successfully."

