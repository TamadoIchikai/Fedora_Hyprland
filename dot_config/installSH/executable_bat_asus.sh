#!/usr/bin/env bash
set -euo pipefail

REPO="tshakalekholoane/bat"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
INSTALL_DIR="$HOME/Downloads/Systems/bat_asus"
BINARY_PATH="${INSTALL_DIR}/bat"
SYMLINK_PATH="/usr/local/bin/bat"

echo ">>> Detecting latest release of ${REPO}..."
# Get the first browser_download_url from assets (should be the bat binary)
DOWNLOAD_URL=$(curl -s "${API_URL}" \
  | grep '"browser_download_url"' \
  | head -n 1 \
  | cut -d '"' -f 4)

if [ -z "${DOWNLOAD_URL}" ]; then
  echo "ERROR: Could not find download URL from GitHub API."
  exit 1
fi

echo ">>> Latest release download URL:"
echo "    ${DOWNLOAD_URL}"

echo ">>> Creating install directory: ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"

echo ">>> Downloading bat to ${BINARY_PATH}..."
curl -L "${DOWNLOAD_URL}" -o "${BINARY_PATH}"

echo ">>> Making bat executable..."
chmod +x "${BINARY_PATH}"

echo ">>> Creating (or updating) symlink at ${SYMLINK_PATH}..."
sudo ln -sf "${BINARY_PATH}" "${SYMLINK_PATH}"

echo ">>> Done! Testing:"
bat --version || bat --help || true

echo ">>> Installation finished. You should now be able to run 'bat' from anywhere."
