#!/usr/bin/env bash

set -euo pipefail

# --- Config ---
BASE_DIR="${HOME}/Downloads/Studies"
DOWNLOAD_DIR="${BASE_DIR}/Zotero"
DESKTOP_DIR="${HOME}/.local/share/applications"
TMP_TARBALL="$(mktemp /tmp/zotero-XXXXXX.tar.xz)"

echo "=== Zotero Installer Script ==="

# --- 1. Ensure directories exist ---
mkdir -p "${BASE_DIR}"
mkdir -p "${DESKTOP_DIR}"

# --- 2. Download ---
echo "[+] Downloading latest Zotero to /tmp..."

if ! curl --fail --show-error -L \
    "https://www.zotero.org/download/client/dl?channel=release&platform=linux-x86_64" \
    -o "${TMP_TARBALL}"; then
    echo "[-] Download failed"
    exit 1
fi

# --- 2.1 Validate ---
if [[ ! -s "${TMP_TARBALL}" ]]; then
    echo "[-] Downloaded file is empty"
    rm "${TMP_TARBALL}" 2>/dev/null || true
    exit 1
fi

# --- 3. Extract into BASE_DIR (staging area) ---
echo "[+] Extracting into ${BASE_DIR}..."
if ! tar -xJf "${TMP_TARBALL}" -C "${BASE_DIR}"; then
    echo "[-] Extraction failed"
    rm "${TMP_TARBALL}" 2>/dev/null || true
    exit 1
fi

# --- 4. Locate extracted directory ---
EXTRACTED_DIR="$(find "${BASE_DIR}" -maxdepth 1 -type d -name 'Zotero*' ! -name 'Zotero' | head -n 1)"

if [[ -z "${EXTRACTED_DIR}" ]]; then
    echo "[-] Extraction failed: directory not found"
    rm "${TMP_TARBALL}" 2>/dev/null || true
    exit 1
fi

# --- 5. Remove old Zotero (no -rf) ---
if [[ -d "${DOWNLOAD_DIR}" ]]; then
    echo "[+] Removing old Zotero directory..."
    rm -r "${DOWNLOAD_DIR}"
fi

# --- 6. Move into final location ---
echo "[+] Moving to ${DOWNLOAD_DIR}..."
mv "${EXTRACTED_DIR}" "${DOWNLOAD_DIR}"

# --- 7. Cleanup tarball ---
rm "${TMP_TARBALL}"

# --- 8. Create .desktop file (no symlink) ---
DESKTOP_FILE_TARGET="${DESKTOP_DIR}/zotero.desktop"

echo "[+] Creating desktop entry..."

cat > "${DESKTOP_FILE_TARGET}" <<EOF
[Desktop Entry]
Name=Zotero
Exec=${DOWNLOAD_DIR}/zotero %U
Icon=${DOWNLOAD_DIR}/icons/icon64.png
Type=Application
Terminal=false
Categories=Office;
MimeType=text/plain;x-scheme-handler/zotero;application/x-research-info-systems;text/x-research-info-systems;text/ris;application/x-endnote-refer;application/x-inst-for-Scientific-info;application/mods+xml;application/rdf+xml;application/x-bibtex;text/x-bibtex;application/marc;application/vnd.citationstyles.style+xml
X-GNOME-SingleWindow=true
EOF

chmod +x "${DESKTOP_FILE_TARGET}"

# --- 9. Update desktop database ---
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${DESKTOP_DIR}" || true
fi

echo "[✓] Zotero installed successfully!"
echo "    Location: ${DOWNLOAD_DIR}"
