#!/usr/bin/env bash
set -euo pipefail

# ---- CONFIGURATION ----
# Create a secure, auto-cleaning temporary directory in /tmp
TMP_DIR="$(mktemp -d /tmp/appimage_installer.XXXXXX)"

# Define our apps: "GitHubRepo | AssetRegexPattern | AppName | ExplicitInstallPath"
APPS=(
    "localsend/localsend|linux-x86-64\.AppImage$|LocalSend|$HOME/Downloads/Systems/LocalSend"
    "obsidianmd/obsidian-releases|AppImage$|Obsidian|$HOME/Downloads/Studies/Obsidian"
    "ahrm/sioyek|sioyek-release-linux\.zip$|Sioyek|$HOME/Downloads/Studies/Sioyek"
)

# Define Desktop configurations strictly matching the APPS array indices above.
# Format: "Comment | ExecArgs | Categories | Keywords | MimeType"
DESKTOP_FILES=(
    # 0: LocalSend
    "Share files to nearby devices|%u|Network;Utility;|share;files;network;transfer;|"
    
    # 1: Obsidian
    "Markdown-based knowledge base|%u|Office;Utility;|markdown;notes;knowledge;|"
    
    # 2: Sioyek
    "PDF viewer designed for research papers|%F|Office;Utility;Application;|pdf;viewer;|application/pdf;"
)

# Track if we need to refresh the desktop database at the end
NEEDS_DESKTOP_REFRESH=false

# Bulletproof cleanup function
cleanup() {
    if [[ -z "${TMP_DIR:-}" ]]; then return; fi
    if [[ "$TMP_DIR" == /tmp/* ]]; then
        rm -rf "$TMP_DIR"
    else
        echo "⚠️ Warning: TMP_DIR ($TMP_DIR) is not in /tmp/. Skipping cleanup." >&2
    fi
}
trap cleanup EXIT

# ---- CORE FUNCTIONS ----

print_usage() {
    echo "Usage: ./apps_AppImages.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help                           Show this help message"
    echo "  --list                           List all apps with their index and GitHub link"
    echo "  --list-check                     List all apps and verify download availability"
    echo "  --install all                    Install all available packages (skips unavailable)"
    echo "  --install --explicit <list>      Install specific comma-separated indices (e.g., \"0, 2\")"
    echo "  --install --explicit-range <rng> Install a range of indices (e.g., \"0, 2\" or \"1, BOT\")"
    echo "  --delete <index>                 Delete the AppImage folder and unregister it from the system"
    echo "  --update <index|all>             Re-download and replace an existing AppImage"
}

get_github_url() {
    local repo="$1"
    local pattern="$2"
    local url

    if command -v curl >/dev/null 2>&1; then
        url=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | \
              jq -r --arg pat "$pattern" '.assets[] | select(.name | test($pat; "i")) | .browser_download_url' | \
              grep -v "arm64" | head -n 1)
    else
        url=$(wget -qO- "https://api.github.com/repos/${repo}/releases/latest" | \
              jq -r --arg pat "$pattern" '.assets[] | select(.name | test($pat; "i")) | .browser_download_url' | \
              grep -v "arm64" | head -n 1)
    fi

    if [[ -z "$url" || "$url" == "null" ]]; then
        echo "❌ Error: Could not find asset matching '$pattern' in $repo" >&2
        return 1
    fi
    
    echo "$url"
}

download_file() {
    local url="$1"
    local dest="$2"
    echo "⬇️ Downloading to $dest..."
    if command -v curl >/dev/null 2>&1; then
        curl --fail --show-error -L "$url" -o "$dest"
    else
        wget -q --show-progress -O "$dest" "$url"
    fi
}

extract_archive() {
    local file="$1"
    local dest_dir="$2"
    mkdir -p "$dest_dir"

    if [[ "$file" == *.zip ]]; then
        echo "📦 Extracting $(basename "$file") to $dest_dir..."
        if command -v unzip >/dev/null 2>&1; then
            unzip -q -o "$file" -d "$dest_dir"
        else
            7z x "$file" -o"$dest_dir" -y >/dev/null
        fi
    else
        echo "➡️ No extraction needed. Moving $(basename "$file") to $dest_dir..."
        cp -f "$file" "$dest_dir/"
    fi
}

extract_icon() {
    local appimage_path="$1"
    local app_name_lower="$2"
    local icon_dir="$HOME/.local/share/icons"
    mkdir -p "$icon_dir"
    
    local extract_tmp
    extract_tmp=$(mktemp -d /tmp/appimage_icon_extract.XXXXXX)
    local icon_dest=""
    
    pushd "$extract_tmp" >/dev/null || exit 1
    if "$appimage_path" --appimage-extract >/dev/null 2>&1; then
        if [[ -d "squashfs-root" ]]; then
            local icon_path
            icon_path=$(find squashfs-root -type f \( -iname "*.png" -o -iname "*.svg" \) 2>/dev/null \
              | awk 'BEGIN { IGNORECASE=1 } {
                    p=$0; score=0
                    if (p ~ /\.svg$/) score+=2000
                    if (p ~ /\.png$/) score+=1000
                    if (p ~ /512/) score+=512
                    else if (p ~ /256/) score+=256
                    else if (p ~ /128/) score+=128
                    else if (p ~ /64/) score+=64
                    else if (p ~ /48/) score+=48
                    print score "\t" p
                  }' | sort -nr | head -n 1 | cut -f2-)
            
            if [[ -n "${icon_path:-}" && -f "$icon_path" ]]; then
                local ext="${icon_path##*.}"
                cp -f -- "$icon_path" "$icon_dir/${app_name_lower}.${ext}"
                icon_dest="$icon_dir/${app_name_lower}.${ext}"
            fi
        fi
    fi
    popd >/dev/null || exit 1
    rm -rf "$extract_tmp"
    
    if [[ -z "$icon_dest" ]]; then
        icon_dest="$icon_dir/${app_name_lower}.png"
        if [[ -f /usr/share/pixmaps/gnome-application-x-executable.png ]]; then
            cp -f /usr/share/pixmaps/gnome-application-x-executable.png "$icon_dest"
        else
            icon_dest=""
        fi
    fi
    echo "$icon_dest"
}

# ---- OPERATION HANDLERS ----

do_list() {
    local check_status="$1"
    echo "=== AppImage Packages ==="
    printf "%-5s | %-15s | %-12s | %s\n" "INDEX" "APP NAME" "STATUS" "GITHUB REPO"
    echo "--------------------------------------------------------------------------------"
    
    for i in "${!APPS[@]}"; do
        IFS='|' read -r REPO PATTERN APP_NAME INSTALL_DIR <<< "${APPS[$i]}"
        local status="-"
        
        if [[ "$check_status" == "true" ]]; then
            # Supress the error output to keep the list UI clean
            if get_github_url "$REPO" "$PATTERN" >/dev/null 2>&1; then
                status="Available"
            else
                status="Unavailable"
            fi
        fi
        
        printf "[%-3s] | %-15s | %-12s | https://github.com/%s\n" "$i" "$APP_NAME" "$status" "$REPO"
    done
    echo ""
}

install_app() {
    local i="$1"
    if [[ -z "${APPS[$i]:-}" ]]; then
        echo "❌ Invalid index: $i"
        return 1
    fi

    IFS='|' read -r REPO PATTERN APP_NAME INSTALL_DIR <<< "${APPS[$i]}"
    desktop_info="${DESKTOP_FILES[$i]:-||||}"
    IFS='|' read -r COMMENT EXEC_ARGS CATEGORIES KEYWORDS MIMETYPES <<< "$desktop_info"
    
    echo ""
    echo "========================================"
    echo "Processing [$i] $APP_NAME..."
    echo "========================================"
    
    # 1. Get URL (Fail gracefully if unavailable so `--install all` skips properly)
    DOWNLOAD_URL=$(get_github_url "$REPO" "$PATTERN" || true)
    if [[ -z "$DOWNLOAD_URL" ]]; then
        echo "⚠️ Skipping $APP_NAME: Download URL unavailable."
        return 1
    fi
    echo "🔗 Found URL: $DOWNLOAD_URL"
    
    # 2. Download to /tmp
    FILENAME=$(basename "$DOWNLOAD_URL")
    TMP_DOWNLOAD_PATH="$TMP_DIR/$FILENAME"
    download_file "$DOWNLOAD_URL" "$TMP_DOWNLOAD_PATH"
    
    # 3. Clean old directory and extract
    if [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
        echo "🗑️ Cleaning existing files in $INSTALL_DIR..."
        find "$INSTALL_DIR" -mindepth 1 -exec rm -rf {} +
    fi
    extract_archive "$TMP_DOWNLOAD_PATH" "$INSTALL_DIR"
    
    # 4. Bind binary & Symlinks
    APPIMAGE_PATH=$(find "$INSTALL_DIR" -type f -name "*.AppImage" | head -n 1)
    if [[ -z "$APPIMAGE_PATH" ]]; then
        echo "❌ Error: No AppImage found in $INSTALL_DIR"
        return 1
    fi
    
    echo "🚀 Making AppImage executable..."
    chmod +x "$APPIMAGE_PATH"
    
    BINARY_DIR="$HOME/.local/bin"
    mkdir -p "$BINARY_DIR"
    APPIMAGE_BIN="$BINARY_DIR/${APP_NAME}.AppImage"
    echo "🔗 Linking to $APPIMAGE_BIN"
    ln -sf "$APPIMAGE_PATH" "$APPIMAGE_BIN"
    
    # 5. Extract Icon
    APP_NAME_LOWER="${APP_NAME,,}"
    echo "🖼️  Extracting application icon..."
    ICON_DEST=$(extract_icon "$APPIMAGE_PATH" "$APP_NAME_LOWER")
    
    # 6. Generate Desktop File
    DESKTOP_DIR="$HOME/.local/share/applications"
    mkdir -p "$DESKTOP_DIR"
    DESKTOP_FILE="$DESKTOP_DIR/${APP_NAME_LOWER}.desktop"
    
    echo "📝 Generating desktop shortcut: $DESKTOP_FILE"
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=$COMMENT
Exec="$APPIMAGE_BIN" $EXEC_ARGS
TryExec=$APPIMAGE_BIN
Icon=$ICON_DEST
Terminal=false
StartupNotify=true
Categories=$CATEGORIES
Keywords=$KEYWORDS
EOF

    if [[ -n "$MIMETYPES" ]]; then
        echo "MimeType=$MIMETYPES" >> "$DESKTOP_FILE"
    fi
    chmod +x "$DESKTOP_FILE"
    
    NEEDS_DESKTOP_REFRESH=true
}

update_app() {
    local i="$1"
    if [[ -z "${APPS[$i]:-}" ]]; then
        echo "❌ Invalid index: $i"
        return 1
    fi

    IFS='|' read -r REPO PATTERN APP_NAME INSTALL_DIR <<< "${APPS[$i]}"
    
    echo ""
    echo "========================================"
    echo "Updating [$i] $APP_NAME..."
    echo "========================================"
    
    # 1. Verify Local Installation Exists
    if [[ ! -d "$INSTALL_DIR" ]]; then
        echo "⚠️ Skipping $APP_NAME: Not installed (Directory $INSTALL_DIR not found)"
        return 0
    fi
    
    local old_appimage
    old_appimage=$(find "$INSTALL_DIR" -maxdepth 1 -type f -name "*.AppImage" | head -n 1)
    if [[ -z "$old_appimage" ]]; then
        echo "⚠️ Skipping $APP_NAME: No existing .AppImage found in $INSTALL_DIR"
        return 0
    fi

    # 2. Fetch Latest URL
    DOWNLOAD_URL=$(get_github_url "$REPO" "$PATTERN" || true)
    if [[ -z "$DOWNLOAD_URL" ]]; then
        echo "⚠️ Skipping $APP_NAME: Download URL unavailable."
        return 1
    fi
    echo "🔗 Found URL: $DOWNLOAD_URL"

    # 3. Download to /tmp
    FILENAME=$(basename "$DOWNLOAD_URL")
    TMP_DOWNLOAD_PATH="$TMP_DIR/$FILENAME"
    download_file "$DOWNLOAD_URL" "$TMP_DOWNLOAD_PATH"

    # 4. Remove old AppImage and extract new one
    echo "🗑️ Removing old AppImage file(s)..."
    find "$INSTALL_DIR" -maxdepth 1 -type f -name "*.AppImage" -exec rm -f {} +
    
    extract_archive "$TMP_DOWNLOAD_PATH" "$INSTALL_DIR"

    # 5. Bind binary & update Symlinks (in case filename/version changed)
    APPIMAGE_PATH=$(find "$INSTALL_DIR" -type f -name "*.AppImage" | head -n 1)
    if [[ -z "$APPIMAGE_PATH" ]]; then
        echo "❌ Error: No AppImage found after extraction in $INSTALL_DIR"
        return 1
    fi
    
    echo "🚀 Making new AppImage executable..."
    chmod +x "$APPIMAGE_PATH"
    
    BINARY_DIR="$HOME/.local/bin"
    APPIMAGE_BIN="$BINARY_DIR/${APP_NAME}.AppImage"
    echo "🔗 Updating symlink to $APPIMAGE_BIN"
    ln -sf "$APPIMAGE_PATH" "$APPIMAGE_BIN"
    
    echo "✅ Update complete for $APP_NAME!"
}

delete_app() {
    local i="$1"
    if [[ -z "${APPS[$i]:-}" ]]; then
        echo "❌ Invalid index: $i"
        return 1
    fi

    IFS='|' read -r REPO PATTERN APP_NAME INSTALL_DIR <<< "${APPS[$i]}"
    
    echo ""
    echo "🗑️  Deleting [$i] $APP_NAME..."
    
    # 1. Wipe the explicit installation folder
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "Removing installation directory: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    fi
    
    # 2. Call the external AppImageManager to clean up system symlinks/icons/desktop
    local manager_script="$HOME/.local/bin/AppImageManager.sh"
    if command -v "$manager_script" >/dev/null 2>&1 || [[ -x "$manager_script" ]]; then
        echo "🧹 Invoking system cleanup via AppImageManager.sh..."
        # Your AppImageManager script uses 'delete' (without dashes) and accepts the App Name
        "$manager_script" delete "$APP_NAME" || true
    else
        echo "⚠️ Warning: AppImageManager.sh not found at $manager_script. System icons/desktop files remain."
    fi
}

# ---- CLI ARGUMENT PARSER ----

if [[ $# -eq 0 ]]; then
    print_usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            print_usage
            exit 0
            ;;
        --list)
            do_list "false"
            exit 0
            ;;
        --list-check)
            do_list "true"
            exit 0
            ;;
        --install)
            shift
            if [[ $# -eq 0 ]]; then echo "❌ Missing arguments for --install"; exit 1; fi
            
            if [[ "$1" == "all" ]]; then
                for i in "${!APPS[@]}"; do install_app "$i" || true; done
                shift
                
            elif [[ "$1" == "--explicit" ]]; then
                shift
                IFS=',' read -ra IDX_ARRAY <<< "$1"
                for idx in "${IDX_ARRAY[@]}"; do
                    # Remove any spaces around the number
                    install_app "${idx// /}" || true
                done
                shift
                
            elif [[ "$1" == "--explicit-range" ]]; then
                shift
                IFS=',' read -ra IDX_ARRAY <<< "$1"
                start="${IDX_ARRAY[0]// /}"
                end="${IDX_ARRAY[1]// /}"
                
                # Check for BOT keyword (case insensitive)
                if [[ "${end^^}" == "BOT" ]]; then
                    end=$((${#APPS[@]} - 1))
                fi
                
                for (( idx=start; idx<=end; idx++ )); do
                    install_app "$idx" || true
                done
                shift
            else
                echo "❌ Invalid argument for --install: $1"
                exit 1
            fi
            ;;
        --delete)
            shift
            if [[ $# -eq 0 ]]; then echo "❌ Missing arguments for --delete"; exit 1; fi
            delete_app "$1"
            shift
            ;;
        --update)
            shift
            if [[ $# -eq 0 ]]; then echo "❌ Missing arguments for --update"; exit 1; fi
            if [[ "$1" == "all" ]]; then
                for i in "${!APPS[@]}"; do update_app "$i" || true; done
            else
                update_app "$1" || true
            fi
            shift
            ;;
        *)
            echo "❌ Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# ---- FINALIZATION ----

if [[ "$NEEDS_DESKTOP_REFRESH" == "true" ]]; then
    echo ""
    echo "🔄 Refreshing system desktop shortcut database..."
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    fi
    echo "✅ Operation successfully completed!"
fi