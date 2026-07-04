#!/usr/bin/env bash
set -euo pipefail

# ---- ARGUMENT PARSING ----
if [[ $# -eq 0 ]]; then
    echo "❌ Missing argument."
    echo "👉 Usage: sudo $0 --install | --update"
    exit 1
fi

MODE=""
if [[ "$1" == "--install" ]]; then
    MODE="install"
elif [[ "$1" == "--update" ]]; then
    MODE="update"
else
    echo "❌ Invalid flag: $1"
    echo "👉 Usage: sudo $0 --install | --update"
    exit 1
fi

# ---- ROOT PRIVILEGE CHECK ----
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root." >&2
   echo "👉 Please run again using: sudo $0 $1" >&2
   exit 1
fi

# ---- CONFIGURATION ----
INSTALL_DIR="/opt/zen"
TMP_DIR="$(mktemp -d /tmp/zen_installer.XXXXXX)"
DESKTOP_FILE="/usr/share/applications/zen.desktop"
GLOBAL_BIN="/usr/local/bin/zen"
BIN_PATH="$INSTALL_DIR/zen"
ICON_PATH="$INSTALL_DIR/browser/chrome/icons/default/default64.png"

# Install-level Config Backup Variables (For Updates)
INPUT_PREFIX="/mnt/sda2"
INPUT_BROWSER="AA_Zen"
INPUT_INSTALL="${INPUT_PREFIX}/Customization/AA_Browsers/${INPUT_BROWSER}/installation folder"
INIT_OUTPUT_INSTALL="/opt/zen"

# ---- SAFETY CLEANUP ----
cleanup() {
    if [[ -z "${TMP_DIR:-}" ]]; then return; fi
    if [[ "$TMP_DIR" == /tmp/* ]]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

# ---- DEPENDENCY CHECK ----
for cmd in curl jq tar awk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Error: '$cmd' is required but not installed." >&2
        exit 1
    fi
done

echo "========================================"
echo "      Zen Browser System Manager        "
echo "========================================"

# ---- MODE: INSTALL CHECK ----
if [[ "$MODE" == "install" ]]; then
    if [[ -x "$GLOBAL_BIN" ]] || [[ -d "$INSTALL_DIR" ]]; then
        echo "⚠️ Zen browser already installed, use flag --update to check and install new updates"
        exit 0
    fi
    echo "🚀 Starting fresh installation..."
fi

# ---- FETCH LATEST VERSION DATA ----
echo "🔍 Checking latest release from GitHub..."
REPO="zen-browser/desktop"
PATTERN="linux-x86_64\\.tar\\.xz$"

API_RESPONSE=$(curl -s "https://api.github.com/repos/${REPO}/releases")
RELEASE_JSON=$(echo "$API_RESPONSE" | jq -r --arg pat "$PATTERN" 'map(select(.assets[]?.name | test($pat; "i"))) | .[0]')

if [[ -z "$RELEASE_JSON" || "$RELEASE_JSON" == "null" ]]; then
    echo "❌ Error: Could not fetch release data from GitHub." >&2
    exit 1
fi

LATEST_VERSION=$(echo "$RELEASE_JSON" | jq -r '.tag_name')
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r --arg pat "$PATTERN" '.assets[]? | select(.name | test($pat; "i")) | .browser_download_url' | head -n 1)

# ---- MODE: UPDATE CHECK ----
if [[ "$MODE" == "update" ]]; then
    if [[ ! -x "$GLOBAL_BIN" ]]; then
        echo "❌ Zen browser is not installed yet or not found at $GLOBAL_BIN."
        echo "👉 Please run: sudo $0 --install"
        exit 1
    fi

    CURRENT_VERSION=$("$GLOBAL_BIN" --version 2>/dev/null | awk '{print $NF}' || echo "unknown")

    echo "📦 Current version: $CURRENT_VERSION"
    echo "🌟 Latest version:  $LATEST_VERSION"

    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        echo "✅ You are already up to date! No action required."
        exit 0
    fi
    
    echo "🚀 Update available! ($CURRENT_VERSION -> $LATEST_VERSION)"
    
    read -r -p "❓ Do you want to download and install this update? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo "❌ Update cancelled by user."
        exit 0
    fi

    echo "✅ Proceeding with download..."
fi

# ---- CORE INSTALL/UPDATE LOGIC ----
echo "🔗 Download URL: $DOWNLOAD_URL"

FILENAME=$(basename "$DOWNLOAD_URL")
TMP_DOWNLOAD_PATH="$TMP_DIR/$FILENAME"

echo "⬇️ Downloading to temporary directory..."
curl --fail --show-error -L "$DOWNLOAD_URL" -o "$TMP_DOWNLOAD_PATH"

mkdir -p "$INSTALL_DIR"
if [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
    echo "🗑️ Cleaning existing files in $INSTALL_DIR..."
    find "$INSTALL_DIR" -mindepth 1 -exec rm -rf {} +
fi

echo "📦 Extracting files..."
tar -xf "$TMP_DOWNLOAD_PATH" -C "$INSTALL_DIR" --strip-components=1

echo "🔗 Linking binary to $GLOBAL_BIN..."
ln -sf "$BIN_PATH" "$GLOBAL_BIN"

echo "➡️ Creating system-wide desktop entry..."
mkdir -p "$(dirname "$DESKTOP_FILE")"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Zen Browser
Comment=Zen browser
Exec=$GLOBAL_BIN %U
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
Icon=$ICON_PATH
EOF

chmod 644 "$DESKTOP_FILE"
chmod +x "$DESKTOP_FILE" || true

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "/usr/share/applications" >/dev/null 2>&1 || true
fi

# ---- POST-ACTION ROUTING ----
if [[ "$MODE" == "install" ]]; then
    echo ""
    echo "✅ Installation complete! You can now launch Zen Browser."
    echo "👉 Remember to manually run your apply script to configure your profile."
else
    echo ""
    echo "✅ Update to $LATEST_VERSION complete!"
    echo ""
    echo "========================================"
    echo "    Restoring Install Configurations    "
    echo "========================================"
    
    OUTPUT_INSTALL=""
    echo "🔍 Searching for actual Install Dir inside $INIT_OUTPUT_INSTALL..."

    if [[ -d "$INIT_OUTPUT_INSTALL" ]]; then
        while IFS= read -r possible_zen; do
            candidate_dir="$(dirname "$possible_zen")"
            if [[ -f "$candidate_dir/zen" && -f "$candidate_dir/zen-bin" && -d "$candidate_dir/defaults" ]]; then
                OUTPUT_INSTALL="$candidate_dir"
                break
            fi
        done < <(find "$INIT_OUTPUT_INSTALL" -type f -name "zen" 2>/dev/null)
    fi

    if [[ -n "$OUTPUT_INSTALL" ]]; then
        echo "✅ Found OUTPUT_INSTALL: $OUTPUT_INSTALL"
        read -p "❓ Restore install configs to this directory? [y/N]: " confirm_inst
        
        if [[ "$confirm_inst" =~ ^[Yy]$ ]]; then
            copy_install_file() {
                local src_file="$1"
                local dest_dir="$2"
                
                if [[ -f "$src_file" ]]; then
                    if [[ ! -d "$dest_dir" ]]; then
                        echo "  -> ❌ Skipped $(basename "$src_file"): Destination folder $dest_dir does not exist!"
                        return
                    fi
                    cp "$src_file" "$dest_dir/"
                    echo "  -> Copied $(basename "$src_file") to $dest_dir"
                else
                    echo "  -> ⚠️ Skipped $(basename "$src_file") (Not found in INPUT_INSTALL)"
                fi
            }

            copy_install_file "$INPUT_INSTALL/config.js" "$OUTPUT_INSTALL"
            copy_install_file "$INPUT_INSTALL/config-prefs.js" "$OUTPUT_INSTALL/defaults/pref"
            echo "✅ Install configurations successfully restored!"
        else
            echo "⏭️  Skipping OUTPUT_INSTALL copy."
        fi
    else
        echo "❌ OUTPUT_INSTALL not found in $INIT_OUTPUT_INSTALL. Skipping config restore."
    fi
fi
