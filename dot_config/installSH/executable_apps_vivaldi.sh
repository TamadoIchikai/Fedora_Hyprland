#!/usr/bin/env bash
set -Eeuxo pipefail

# Download and install latest Vivaldi Stable RPM x86_64
# Safe behavior:
# - No force flags
# - No rm -f
# - Does not overwrite an existing RPM
# - Verifies that the resolved file is an x86_64.rpm
# - Installs using dnf

BASE_URL="https://vivaldi.com/download/vivaldi-stable.x86_64.rpm"
DOWNLOAD_DIR="/tmp"

command -v curl >/dev/null 2>&1 || {
    echo "Error: curl is required but not installed." >&2
    exit 1
}

command -v dnf >/dev/null 2>&1 || {
    echo "Error: dnf is required but not installed." >&2
    exit 1
}

# Resolve latest real download URL after redirects
FINAL_URL="$(
    curl \
        --location \
        --head \
        --silent \
        --show-error \
        --write-out '%{url_effective}' \
        --output /dev/null \
        "$BASE_URL"
)"

FILENAME="$(basename "$FINAL_URL")"

# Validate required RPM architecture/extension
case "$FILENAME" in
    vivaldi-stable-*.x86_64.rpm)
        ;;
    *)
        echo "Error: resolved file is not a Vivaldi stable x86_64 RPM:" >&2
        echo "$FILENAME" >&2
        exit 1
        ;;
esac

DEST_PATH="${DOWNLOAD_DIR}/${FILENAME}"

if [[ -e "$DEST_PATH" ]]; then
    echo "File already exists, using existing RPM:"
    echo "$DEST_PATH"
else
    TMP_PATH="$(mktemp "${DOWNLOAD_DIR}/vivaldi-stable.XXXXXX.partial")"

    cleanup() {
        if [[ -e "$TMP_PATH" ]]; then
            rm "$TMP_PATH"
        fi
    }
    trap cleanup EXIT

    curl \
        --location \
        --show-error \
        --output "$TMP_PATH" \
        "$FINAL_URL"

    if [[ ! -s "$TMP_PATH" ]]; then
        echo "Error: downloaded file is empty." >&2
        exit 1
    fi

    mv -n "$TMP_PATH" "$DEST_PATH"
    trap - EXIT

    echo "Downloaded:"
    echo "$DEST_PATH"
fi

echo "Installing Vivaldi using dnf..."
sudo dnf install -y "$DEST_PATH"

echo "Vivaldi installation completed."
