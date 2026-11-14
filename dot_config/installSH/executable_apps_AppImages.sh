#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/state.sh
source "$SCRIPT_DIR/lib/state.sh"

# Optional GitHub token support (avoids anonymous API rate limits). The helper
# checks exported GITHUB_TOKEN/GH_TOKEN first, then token files, so login-time
# checks do not depend on shell exports.
GITHUB_TOKEN="$(installsh_github_token 2>/dev/null || true)"
export GITHUB_TOKEN
CURL_AUTH=()
WGET_AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    WGET_AUTH=(--header="Authorization: Bearer ${GITHUB_TOKEN}")
fi

# ---- CONFIGURATION ----
# Create a secure, auto-cleaning temporary directory in /tmp
TMP_DIR="$(mktemp -d /tmp/appimage_installer.XXXXXX)"

# Define our apps: "GitHubRepo | AssetRegexPattern | AppName | ExplicitInstallPath | Mode(optional)"
#
# Mode (optional 5th field, empty = run the AppImage as-is):
#   unpack-system-qt  For Qt AppImages that bundle their own Qt without theme
#                     plugins (they always look light). The AppImage is kept in
#                     InstallPath for version tracking, but it is also unpacked
#                     into InstallPath/unpacked with the bundled Qt/libs removed,
#                     so the binary runs on the system Qt (qt6ct/Kvantum/Wayland).
#                     The ~/.local/bin/<AppName>.AppImage link points at that binary.
APPS=(
    "localsend/localsend|linux-x86-64\.AppImage$|LocalSend|$HOME/Downloads/Systems/LocalSend"
    "ahrm/sioyek|sioyek-release-linux\.zip$|Sioyek|$HOME/Downloads/Studies/Sioyek"
    "imputnet/helium-linux|x86_64\.AppImage$|Helium|$HOME/Downloads/Systems/Helium"
    "benapetr/TuxManager|x86_64\.AppImage$|TuxManager|$HOME/Downloads/Systems/TuxManager|unpack-system-qt"
)

# Define Desktop configurations strictly matching the APPS array indices above.
# Format: "Comment | ExecArgs | Categories | Keywords | MimeType"
DESKTOP_FILES=(
    # 0: LocalSend
    "Share files to nearby devices|%u|Network;Utility;|share;files;network;transfer;|"
    
    # 2: Sioyek
    "PDF viewer designed for research papers|%F|Office;Utility;Application;|pdf;viewer;|application/pdf;"
    
    # 3: Helium
    "Private, fast, and honest web browser|%u|Network;WebBrowser;|browser;helium;web;privacy;|text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;"

    # 3: TuxManager
    "Linux system monitor inspired by Windows Task Manager||System;Monitor;|task;manager;process;cpu;memory;|"
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
    echo "Usage: ./app_AppImage.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help                           Show this help message"
    echo "  --list                           List all apps with their index and GitHub link"
    echo "  --list-check                     List all apps and verify download availability"
    echo "  --install all                    Install all available packages (skips unavailable)"
    echo "  --install --explicit <list>      Install specific comma-separated indices (e.g., \"0, 2\")"
    echo "  --install --explicit-range <rng> Install a range of indices (e.g., \"0, 2\" or \"1, BOT\")"
    echo "  --delete <index>                 Delete the AppImage folder and unregister it from the system"
    echo "  --update <index|all>             Update one AppImage, or all installed AppImages"
    echo "  --check <index|all>              Report installed/latest versions without downloading"
    echo "  --register                       Write update-checker flags for already-installed apps"
}

get_github_release_info() {
    local repo="$1"
    local pattern="$2"
    local page=1
    local response
    local result

    # The /releases/latest endpoint is not enough here:
    # GitHub can make the newest release mobile-only (e.g. .apk),
    # while the newest release containing an AppImage is an older one.
    while :; do
        # Bound pagination so a one-shot update check cannot run forever.
        if (( page > 5 )); then
            break
        fi

        if command -v curl >/dev/null 2>&1; then
            response=$(curl -fsSL --connect-timeout 5 --max-time 20 \
                "${CURL_AUTH[@]}" \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/repos/${repo}/releases?per_page=100&page=${page}") || return 1
        else
            response=$(wget -qO- --timeout=20 \
                "${WGET_AUTH[@]}" \
                --header="Accept: application/vnd.github+json" \
                "https://api.github.com/repos/${repo}/releases?per_page=100&page=${page}") || return 1
        fi

        # Find the first release (GitHub returns releases newest first)
        # that contains an asset matching the requested pattern.
        result=$(jq -r --arg pat "$pattern" '
            .[]
            | select(.draft == false and .prerelease == false)
            | . as $release
            | $release.assets[]
            | select(.name | test($pat; "i"))
            | select(.name | test("arm64"; "i") | not)
            | [$release.tag_name, .name, .browser_download_url]
            | @tsv
        ' <<< "$response" | head -n 1)

        if [[ -n "$result" ]]; then
            echo "$result"
            return 0
        fi

        # No more releases to search.
        local count
        count=$(jq 'length' <<< "$response")
        if [[ "$count" -lt 100 ]]; then
            break
        fi

        ((page++))
    done

    echo "❌ Error: Could not find any release asset matching '$pattern' in $repo" >&2
    return 1
}

get_github_url() {
    local repo="$1"
    local pattern="$2"
    local info

    info=$(get_github_release_info "$repo" "$pattern") || return 1
    cut -f3 <<< "$info"
}

get_github_version() {
    local repo="$1"
    local pattern="$2"
    local info

    info=$(get_github_release_info "$repo" "$pattern") || return 1
    cut -f1 <<< "$info"
}

normalize_version() {
    local version="$1"

    # Remove common prefixes such as v and version.
    version="${version#v}"
    version="${version#V}"
    version="${version#version-}"
    version="${version#Version-}"
    version="${version#version_}"
    version="${version#Version_}"

    # Keep only the version-looking part when possible.
    if [[ "$version" =~ ([0-9]+([.][0-9]+)+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "$version"
    fi
}

get_local_appimage_version() {
    local appimage_path="$1"
    local filename
    local version=""

    filename="$(basename "$appimage_path")"

    # First try the filename. This is reliable for apps such as
    # Obsidian where the AppImage name contains the release version.
    if [[ "$filename" =~ ([0-9]+([.][0-9]+)+) ]]; then
        version="${BASH_REMATCH[1]}"
    fi

    # If the filename has no version, ask AppImage itself.
    # NOTE: some AppImages print --appimage-version to stderr, and the runtime
    # version is not the application version. Only accept a dotted version.
    if [[ -z "$version" ]]; then
        local raw
        raw=$(timeout 5 "$appimage_path" --appimage-version 2>&1 | head -n 1 || true)
        if [[ "$raw" =~ ([0-9]+([.][0-9]+)+) ]]; then
            version="${BASH_REMATCH[1]}"
        fi
    fi

    # Last resort: ask the application itself (bounded so it cannot hang).
    if [[ -z "$version" ]]; then
        local raw
        raw=$(timeout 5 "$appimage_path" --version 2>/dev/null | head -n 1 || true)
        if [[ "$raw" =~ ([0-9]+([.][0-9]+)+) ]]; then
            version="${BASH_REMATCH[1]}"
        fi
    fi

    [[ -n "$version" ]] && echo "$version"
}

version_is_newer() {
    local current
    local latest

    current="$(normalize_version "$1")"
    latest="$(normalize_version "$2")"

    [[ -n "$latest" ]] || return 1
    [[ -z "$current" ]] && return 0

    # sort -V handles normal dotted versions such as 1.10.0 > 1.9.12.
    [[ "$(printf '%s\n' "$current" "$latest" | sort -V | tail -n 1)" == "$latest" \
        && "$current" != "$latest" ]]
}

check_app() {
    local i="$1"

    if [[ -z "${APPS[$i]:-}" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "?" "unknown" "unknown" "unknown" "error" "invalid index"
        return 1
    fi

    IFS='|' read -r REPO PATTERN APP_NAME INSTALL_DIR MODE <<< "${APPS[$i]}"

    local old_appimage current_version latest_version state detail release_info
    old_appimage="$(find "$INSTALL_DIR" -maxdepth 1 -type f -iname '*.AppImage' 2>/dev/null | head -n 1 || true)"

    if [[ -z "$old_appimage" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$i" "$APP_NAME" "unknown" "unknown" "not-installed" "no AppImage found"
        return 0
    fi

    current_version="$(get_local_appimage_version "$old_appimage" || true)"

    release_info="$(get_github_release_info "$REPO" "$PATTERN" 2>/dev/null || true)"
    if [[ -z "$release_info" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$i" "$APP_NAME" "${current_version:-unknown}" "unknown" "error" "repository check failed"
        return 0
    fi

    latest_version="$(cut -f1 <<< "$release_info")"
    state="error"
    detail=""

    if [[ -z "$current_version" ]]; then
        detail="installed version unknown"
    elif [[ -z "$latest_version" ]]; then
        detail="latest version unknown"
    elif [[ "$(normalize_version "$current_version")" == "$(normalize_version "$latest_version")" ]]; then
        state="current"
    elif version_is_newer "$current_version" "$latest_version"; then
        state="update"
    else
        state="newer"
        detail="installed version is newer"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$i" "$APP_NAME" "${current_version:-unknown}" "${latest_version:-unknown}" "$state" "$detail"
}

do_check() {
    local target="$1"
    local i

    printf 'index\tname\tcurrent\tlatest\tstate\tdetail\n'

    if [[ "$target" == "all" ]]; then
        for i in "${!APPS[@]}"; do
            check_app "$i" || true
        done
        return 0
    fi

    if [[ ! "$target" =~ ^[0-9]+$ ]] || [[ -z "${APPS[$target]:-}" ]]; then
        echo "❌ Invalid index: $target" >&2
        return 1
    fi

    check_app "$target"
}

# Write flags for AppImages that are already installed, without downloading.
do_register() {
    local i repo pattern app_name install_dir
    local appimage_path app_name_lower installed_version binary

    for i in "${!APPS[@]}"; do
        IFS='|' read -r repo pattern app_name install_dir mode <<< "${APPS[$i]}"

        appimage_path="$(find "$install_dir" -maxdepth 1 -type f -iname '*.AppImage' 2>/dev/null | head -n 1 || true)"
        if [[ -z "$appimage_path" ]]; then
            printf 'skip: %s not installed (%s)\n' "$app_name" "$install_dir" >&2
            continue
        fi

        app_name_lower="${app_name,,}"
        installed_version="$(get_local_appimage_version "$appimage_path" || true)"
        binary="$HOME/.local/bin/${app_name}.AppImage"

        installsh_flag_write "appimage-${app_name_lower}" \
            "name=$app_name" \
            "kind=appimage" \
            "source=apps_AppImages.sh" \
            "source_index=$i" \
            "repo=$repo" \
            "pattern=$pattern" \
            "install_dir=$install_dir" \
            "binary=$binary" \
            "installed_version=${installed_version:-unknown}" \
            "updated_at=$(date -Is)" || true

        printf 'registered: %s %s\n' "$app_name" "${installed_version:-unknown}"
    done
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
    # Optional: an already-unpacked AppImage tree to search instead of running
    # --appimage-extract (used by the unpack-system-qt mode).
    local src_root="${3:-}"
    local icon_dir="$HOME/.local/share/icons"
    mkdir -p "$icon_dir"
    
    local extract_tmp
    extract_tmp=$(mktemp -d /tmp/appimage_icon_extract.XXXXXX)
    local icon_dest=""
    
    pushd "$extract_tmp" >/dev/null || exit 1
    local search_root="squashfs-root"
    if [[ -n "$src_root" && -d "$src_root" ]]; then
        search_root="$src_root"
    elif ! "$appimage_path" --appimage-extract >/dev/null 2>&1; then
        search_root=""
    fi
    if [[ -n "$search_root" ]]; then
        if [[ -d "$search_root" ]]; then
            local icon_path
            icon_path=$(find "$search_root" -type f \( -iname "*.png" -o -iname "*.svg" \) 2>/dev/null \
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

# Unpack an AppImage (without executing it) into <install_dir>/unpacked and
# strip its bundled Qt + libraries so the binary runs on the system Qt and
# picks up the system Qt theme (qt6ct, Kvantum, Wayland, ...).
# Prints the path of the main binary on stdout; messages go to stderr.
unpack_system_qt() {
    local appimage_path="$1"
    local install_dir="$2"
    local dest="$install_dir/unpacked"

    if ! command -v 7z >/dev/null 2>&1; then
        echo "❌ Error: 7z not found (install p7zip / 7zip)." >&2
        return 1
    fi
    if ! ldconfig -p 2>/dev/null | grep -q 'libQt6Widgets\.so\.6'; then
        echo "❌ Error: system Qt6 not found (install qt6-qtbase-gui)." >&2
        return 1
    fi

    echo "📦 Unpacking $(basename "$appimage_path") to $dest (system Qt mode)..." >&2
    rm -rf "$dest"
    mkdir -p "$dest"
    if ! 7z x -y -o"$dest" "$appimage_path" >/dev/null; then
        echo "❌ Error: failed to unpack $appimage_path" >&2
        return 1
    fi

    # Drop the bundled Qt, its plugins/config and the libraries it pulled in.
    rm -rf "$dest/usr/lib" "$dest/usr/plugins" "$dest/usr/translations" "$dest/usr/bin/qt.conf"

    # Main binary: AppRun.wrapped (linuxdeploy) links to it; else use the
    # top-level .desktop Exec= entry.
    local bin=""
    if [[ -L "$dest/AppRun.wrapped" ]]; then
        bin="$dest/$(readlink "$dest/AppRun.wrapped")"
    fi
    if [[ ! -f "$bin" ]]; then
        local desktop exec_name
        desktop="$(find "$dest" -maxdepth 1 -name '*.desktop' | head -n 1)"
        exec_name="$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$desktop" 2>/dev/null | head -n 1)"
        bin="$dest/usr/bin/$(basename "${exec_name:-missing}")"
    fi
    if [[ ! -f "$bin" ]]; then
        echo "❌ Error: could not find the main binary in $dest" >&2
        return 1
    fi
    chmod +x "$bin"

    local missing
    missing="$(ldd "$bin" 2>/dev/null | grep 'not found' || true)"
    if [[ -n "$missing" ]]; then
        echo "❌ Error: missing system libraries for $(basename "$bin"):" >&2
        echo "$missing" >&2
        return 1
    fi

    echo "$bin"
}

# ---- OPERATION HANDLERS ----

do_list() {
    local check_status="$1"
    echo "=== AppImage Packages ==="
    printf "%-5s | %-15s | %-12s | %s\n" "INDEX" "APP NAME" "STATUS" "GITHUB REPO"
    echo "--------------------------------------------------------------------------------"
    
    for i in "${!APPS[@]}"; do
        IFS='|' read -r REPO PATTERN APP_NAME INSTALL_DIR MODE <<< "${APPS[$i]}"
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

    IFS='|' read -r REPO PATTERN APP_NAME INSTALL_DIR MODE <<< "${APPS[$i]}"
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
    local LINK_TARGET="$APPIMAGE_PATH" ICON_SRC=""
    if [[ "${MODE:-}" == "unpack-system-qt" ]]; then
        LINK_TARGET=$(unpack_system_qt "$APPIMAGE_PATH" "$INSTALL_DIR") || return 1
        ICON_SRC="$INSTALL_DIR/unpacked"
    fi
    echo "🔗 Linking to $APPIMAGE_BIN"
    ln -sf "$LINK_TARGET" "$APPIMAGE_BIN"
    
    # 5. Extract Icon
    APP_NAME_LOWER="${APP_NAME,,}"
    echo "🖼️  Extracting application icon..."
    ICON_DEST=$(extract_icon "$APPIMAGE_PATH" "$APP_NAME_LOWER" "$ICON_SRC")
    
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

    # Register this installation so the login update checker can find it.
    local INSTALLED_VERSION
    INSTALLED_VERSION="$(get_local_appimage_version "$APPIMAGE_PATH" || true)"
    installsh_flag_write "appimage-${APP_NAME_LOWER}" \
        "name=$APP_NAME" \
        "kind=appimage" \
        "source=apps_AppImages.sh" \
        "source_index=$i" \
        "repo=$REPO" \
        "pattern=$PATTERN" \
        "install_dir=$INSTALL_DIR" \
        "binary=$APPIMAGE_BIN" \
        "installed_version=${INSTALLED_VERSION:-unknown}" \
        "updated_at=$(date -Is)" || true

    NEEDS_DESKTOP_REFRESH=true
}

update_app() {
    local i="$1"
    if [[ -z "${APPS[$i]:-}" ]]; then
        echo "❌ Invalid index: $i"
        return 1
    fi

    IFS='|' read -r REPO PATTERN APP_NAME INSTALL_DIR MODE <<< "${APPS[$i]}"

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
    old_appimage=$(find "$INSTALL_DIR" -maxdepth 1 -type f -iname "*.AppImage" | head -n 1)
    if [[ -z "$old_appimage" ]]; then
        echo "⚠️ Skipping $APP_NAME: No existing .AppImage found in $INSTALL_DIR"
        return 0
    fi

    # 2. Get the newest GitHub release that actually contains
    #    a matching AppImage. This automatically skips releases
    #    that only contain mobile APKs or other assets.
    local release_info
    release_info=$(get_github_release_info "$REPO" "$PATTERN" || true)
    if [[ -z "$release_info" ]]; then
        echo "⚠️ Skipping $APP_NAME: No AppImage release available."
        return 1
    fi

    local latest_version latest_filename DOWNLOAD_URL
    latest_version="$(cut -f1 <<< "$release_info")"
    latest_filename="$(cut -f2 <<< "$release_info")"
    DOWNLOAD_URL="$(cut -f3 <<< "$release_info")"

    # 3. Detect installed and GitHub versions.
    local current_version
    current_version="$(get_local_appimage_version "$old_appimage" || true)"

    echo "📦 Installed: ${current_version:-unknown}"
    echo "🌐 Latest:    ${latest_version:-unknown}"
    echo "🔗 Found URL: $DOWNLOAD_URL"

    # If we can determine both versions, avoid an unnecessary download.
    if [[ -n "$current_version" && -n "$latest_version" ]]; then
        if [[ "$(normalize_version "$current_version")" == "$(normalize_version "$latest_version")" ]]; then
            echo "✅ $APP_NAME is already up to date."
            return 0
        fi

        if ! version_is_newer "$current_version" "$latest_version"; then
            echo "ℹ️ Installed version is newer than the GitHub AppImage release."
            echo "   Skipping update."
            return 0
        fi

        echo "⬆️ Update available: $current_version → $latest_version"
    else
        echo "⚠️ Could not reliably compare versions; downloading the latest AppImage."
    fi

    # 4. Download to /tmp
    local FILENAME TMP_DOWNLOAD_PATH
    FILENAME="$latest_filename"
    TMP_DOWNLOAD_PATH="$TMP_DIR/$FILENAME"
    download_file "$DOWNLOAD_URL" "$TMP_DOWNLOAD_PATH"

    # 5. Remove old AppImage(s) and extract new one.
    echo "🗑️ Removing old AppImage file(s)..."
    find "$INSTALL_DIR" -maxdepth 1 -type f -iname "*.AppImage" -exec rm -f {} +

    extract_archive "$TMP_DOWNLOAD_PATH" "$INSTALL_DIR"

    # 6. Find the new AppImage.
    local APPIMAGE_PATH
    APPIMAGE_PATH=$(find "$INSTALL_DIR" -type f -iname "*.AppImage" | head -n 1)
    if [[ -z "$APPIMAGE_PATH" ]]; then
        echo "❌ Error: No AppImage found after extraction in $INSTALL_DIR"
        return 1
    fi

    echo "🚀 Making new AppImage executable..."
    chmod +x "$APPIMAGE_PATH"

    # 7. Bind binary & update symlink.
    local BINARY_DIR APPIMAGE_BIN
    BINARY_DIR="$HOME/.local/bin"
    mkdir -p "$BINARY_DIR"
    APPIMAGE_BIN="$BINARY_DIR/${APP_NAME}.AppImage"
    local LINK_TARGET="$APPIMAGE_PATH" ICON_SRC=""
    if [[ "${MODE:-}" == "unpack-system-qt" ]]; then
        LINK_TARGET=$(unpack_system_qt "$APPIMAGE_PATH" "$INSTALL_DIR") || return 1
        ICON_SRC="$INSTALL_DIR/unpacked"
    fi
    echo "🔗 Updating symlink to $APPIMAGE_BIN"
    ln -sf "$LINK_TARGET" "$APPIMAGE_BIN"

    # 8. Refresh icon as well, since an application update can change it.
    local APP_NAME_LOWER ICON_DEST
    APP_NAME_LOWER="${APP_NAME,,}"
    echo "🖼️  Updating application icon..."
    ICON_DEST=$(extract_icon "$APPIMAGE_PATH" "$APP_NAME_LOWER" "$ICON_SRC")

    # Keep the existing desktop entry in sync with the new icon.
    local DESKTOP_FILE
    DESKTOP_FILE="$HOME/.local/share/applications/${APP_NAME_LOWER}.desktop"
    if [[ -f "$DESKTOP_FILE" && -n "$ICON_DEST" ]]; then
        sed -i "s|^Icon=.*|Icon=$ICON_DEST|" "$DESKTOP_FILE"
        NEEDS_DESKTOP_REFRESH=true
    fi

    echo "✅ Update complete for $APP_NAME: ${current_version:-unknown} → ${latest_version:-unknown}"

    # Refresh the installation flag with the new version.
    local INSTALLED_VERSION
    INSTALLED_VERSION="$(get_local_appimage_version "$APPIMAGE_PATH" || true)"
    installsh_flag_write "appimage-${APP_NAME_LOWER}" \
        "name=$APP_NAME" \
        "kind=appimage" \
        "source=apps_AppImages.sh" \
        "source_index=$i" \
        "repo=$REPO" \
        "pattern=$PATTERN" \
        "install_dir=$INSTALL_DIR" \
        "binary=$APPIMAGE_BIN" \
        "installed_version=${INSTALLED_VERSION:-${latest_version:-unknown}}" \
        "updated_at=$(date -Is)" || true
}


delete_app() {
    local i="$1"
    if [[ -z "${APPS[$i]:-}" ]]; then
        echo "❌ Invalid index: $i"
        return 1
    fi

    IFS='|' read -r REPO PATTERN APP_NAME INSTALL_DIR MODE <<< "${APPS[$i]}"
    
    echo ""
    echo "🗑️  Deleting [$i] $APP_NAME..."
    
    # 1. Wipe the explicit installation folder
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "Removing installation directory: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    fi

    # Remove the installation flag so the update checker stops reporting it.
    local APP_NAME_LOWER="${APP_NAME,,}"
    installsh_flag_remove "appimage-${APP_NAME_LOWER}" || true

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
        --check)
            shift
            if [[ $# -eq 0 ]]; then echo "❌ Missing arguments for --check"; exit 1; fi
            do_check "$1"
            exit 0
            ;;
        --register)
            do_register
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
                echo "🔄 Updating all AppImages..."
                for i in "${!APPS[@]}"; do
                    update_app "$i" || true
                done
                echo ""
                echo "✅ Finished processing all AppImages."
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
