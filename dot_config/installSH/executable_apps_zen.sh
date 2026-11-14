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

usage() {
    echo "Usage: sudo $0 --install | --update | --uninstall | --setup-ssd"
    echo "       $0 --check | --register"
    echo ""
    echo "Options:"
    echo "  --install      Install Zen Browser + put its profile/cache on the SSD (root)"
    echo "  --update       Check for and install an update (root)"
    echo "  --uninstall    Remove Zen Browser and its update-check flag (root)"
    echo "  --setup-ssd    Move/link the Zen profile + cache to ${ZEN_SSD_BASE:-/var/home}/<user> (root, re-runnable)"
    echo "  --check        Print current/latest version without changing anything"
    echo "  --register     Register an existing install with update-check"
    echo "  -h, --help     Show this help"
}

# ---- ARGUMENT PARSING ----
if [[ $# -eq 0 ]]; then
    echo "❌ Missing argument."
    echo "👉 Run: $0 --help"
    exit 1
fi

MODE=""
case "$1" in
    --install)   MODE="install" ;;
    --update)    MODE="update" ;;
    --uninstall) MODE="uninstall" ;;
    --check)     MODE="check" ;;
    --register)  MODE="register" ;;
    --setup-ssd) MODE="setup-ssd" ;;
    -h|--help)   MODE="help" ;;
    *)
        echo "❌ Invalid flag: $1"
        echo "👉 Run: $0 --help"
        exit 1
        ;;
esac

if [[ "$MODE" == "help" ]]; then
    usage
    exit 0
fi

# ---- ROOT PRIVILEGE CHECK ----
# --check and --register must work as the desktop user.
if [[ "$MODE" =~ ^(install|update|uninstall|setup-ssd)$ ]] && [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root." >&2
   echo "👉 Please run again using: sudo $0 $1" >&2
   exit 1
fi

# ---- CONFIGURATION ----
INSTALL_DIR="/opt/zen"
TMP_DIR=""
DESKTOP_FILE="/usr/share/applications/zen.desktop"
GLOBAL_BIN="/usr/local/bin/zen"
BIN_PATH="$INSTALL_DIR/zen"
ICON_PATH="$INSTALL_DIR/browser/chrome/icons/default/default64.png"
REPO="zen-browser/desktop"
PATTERN="linux-x86_64\\.tar\\.xz$"

# Install-level Config Backup Variables (For Updates)
INPUT_PREFIX="/mnt/sda2"
INPUT_BROWSER="AA_Zen"
INPUT_INSTALL="${INPUT_PREFIX}/Customization/AA_Browsers/${INPUT_BROWSER}/installation folder"
INIT_OUTPUT_INSTALL="/opt/zen"

# Profile/cache location on the root SSD. ~/.config/zen and ~/.cache/zen become
# symlinks to $ZEN_SSD_BASE/<user>/zen-config and .../zen-cache. Fedora's SELinux
# policy treats /var/home like /home (file_contexts.subs_dist), so labels match
# a normal home dir. The env override exists for testing only.
ZEN_SSD_BASE="${ZEN_SSD_BASE:-/var/home}"
ZEN_SSD_USER=""
ZEN_SSD_BACKUPS=()

# ---- SAFETY CLEANUP ----
cleanup() {
    if [[ -z "${TMP_DIR:-}" ]]; then return; fi
    if [[ "$TMP_DIR" == /tmp/* ]]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

# ---- DEPENDENCY CHECK ----
case "$MODE" in
    install)        DEPS=(curl jq tar awk rsync runuser) ;;
    update)         DEPS=(curl jq tar awk) ;;
    setup-ssd)      DEPS=(rsync runuser) ;;
    check)          DEPS=(curl jq awk) ;;
    *)              DEPS=() ;;
esac

for cmd in "${DEPS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Error: '$cmd' is required but not installed." >&2
        exit 1
    fi
done

zen_current_version() {
    if [[ -x "$GLOBAL_BIN" ]]; then
        "$GLOBAL_BIN" --version 2>/dev/null | awk 'NR == 1 { print $NF }'
    fi
}

# Populate ZEN_LATEST_TAG, ZEN_LATEST_URL, and ZEN_FETCH_ERROR.
zen_fetch_latest() {
    local response info
    local -a auth=()

    ZEN_LATEST_TAG=""
    ZEN_LATEST_URL=""
    ZEN_FETCH_ERROR=""

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    if ! response="$(curl -fsSL --connect-timeout 5 --max-time 20 \
            "${auth[@]}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${REPO}/releases?per_page=100" \
            2>/dev/null)"; then
        ZEN_FETCH_ERROR="repository check failed"
        return 1
    fi

    if grep -qi 'API rate limit exceeded' <<< "$response"; then
        ZEN_FETCH_ERROR="GitHub rate limit reached"
        return 1
    fi

    info="$(jq -r --arg pat "$PATTERN" '
        .[]
        | select(.draft == false and .prerelease == false)
        | . as $release
        | $release.assets[]
        | select(.name | test($pat; "i"))
        | select(.name | test("arm64"; "i") | not)
        | [$release.tag_name, .browser_download_url]
        | @tsv
    ' <<< "$response" 2>/dev/null | head -n 1 || true)"

    if [[ -z "$info" ]]; then
        ZEN_FETCH_ERROR="no matching release asset"
        return 1
    fi

    IFS=$'\t' read -r ZEN_LATEST_TAG ZEN_LATEST_URL <<< "$info"
    ZEN_LATEST_TAG="${ZEN_LATEST_TAG#v}"
    return 0
}

# Print one TSV row: tag, current, latest, state, detail.
zen_check() {
    local current latest state detail

    current="$(zen_current_version || true)"
    latest="unknown"
    state="error"
    detail=""

    if [[ -z "$current" ]]; then
        state="not-installed"
        detail="zen not installed"
    elif ! zen_fetch_latest; then
        detail="${ZEN_FETCH_ERROR:-repository check failed}"
    else
        latest="$ZEN_LATEST_TAG"

        if [[ "$current" == "$latest" ]]; then
            state="current"
        elif [[ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n 1)" == "$latest" ]]; then
            state="update"
        else
            state="newer"
            detail="installed version is newer"
        fi
    fi

    printf 'zen\t%s\t%s\t%s\t%s\n' \
        "${current:-unknown}" "$latest" "$state" "$detail"
    return 0
}

zen_register() {
    local current

    current="$(zen_current_version || true)"
    if [[ -z "$current" ]]; then
        echo "❌ Zen Browser is not installed at $GLOBAL_BIN." >&2
        return 1
    fi

    installsh_flag_write zen \
        "name=Zen Browser" \
        "kind=zen" \
        "source=apps_zen.sh" \
        "install_dir=$INSTALL_DIR" \
        "binary=$GLOBAL_BIN" \
        "installed_version=$current" \
        "updated_at=$(date -Is)"
}

# ---- SSD PROFILE/CACHE SETUP ----
# Run a command as the desktop user (keeps file ownership correct).
zen_as_user() {
    runuser -u "$ZEN_SSD_USER" -- "$@"
}

zen_is_running() {
    pgrep -u "$ZEN_SSD_USER" -x 'zen|zen-bin' >/dev/null 2>&1
}

# zen_link_to_ssd <link> <target> <copy|discard> <label>
# Make <link> a symlink to <target>. Real directories are migrated first
# (copy = rsync + checksum verify, discard = start empty). Never overwrites:
# the old directory is kept as <link>.hdd-bak-<timestamp>.
# NOTE: callers use `|| rc=1`, which disables errexit here, so every
# critical command is checked explicitly.
zen_link_to_ssd() {
    local link="$1" target="$2" mode="$3" label="$4"
    local resolved backup diff_out answer size

    # 1) Already a symlink
    if [[ -L "$link" ]]; then
        resolved="$(readlink -f "$link" 2>/dev/null || true)"
        if [[ -n "$resolved" && "$resolved" == "$(readlink -f "$target" 2>/dev/null || true)" ]]; then
            echo "✅ Zen $label already on SSD: $link -> $target"
        else
            echo "⚠️  Skipped Zen $label: $link points to '${resolved:-?}', not $target. Fix it manually." >&2
        fi
        return 0
    fi

    # 2) Something that is not a directory
    if [[ -e "$link" && ! -d "$link" ]]; then
        echo "⚠️  Skipped Zen $label: $link exists but is not a directory." >&2
        return 0
    fi

    # 3) Missing (fresh install): create target + link before Zen's first start
    if [[ ! -e "$link" ]]; then
        if ! zen_as_user mkdir -p "$(dirname "$link")" "$target" \
           || ! zen_as_user ln -s "$target" "$link"; then
            echo "❌ Could not create $link -> $target" >&2
            return 1
        fi
        echo "✅ Zen $label created on SSD: $link -> $target"
        return 0
    fi

    # 4) Real directory on the old disk: migrate it
    if zen_is_running; then
        echo "❌ Zen is running for $ZEN_SSD_USER. Close it completely, then run: sudo $0 --setup-ssd" >&2
        return 1
    fi
    if [[ -d "$target" && -n "$(ls -A "$target" 2>/dev/null)" ]]; then
        echo "❌ $target already exists and is not empty. Resolve it manually before migrating $link." >&2
        return 1
    fi

    size="$(du -sh "$link" 2>/dev/null | cut -f1 || true)"
    read -r -p "❓ Move Zen $label ($link, ${size:-?}) to $target? [y/N] " answer || answer=""
    if [[ ! "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo "⏭️  Left Zen $label where it is."
        return 0
    fi

    if ! zen_as_user mkdir -p "$target"; then
        echo "❌ Could not create $target" >&2
        return 1
    fi

    if [[ "$mode" == "copy" ]]; then
        echo "📦 Copying Zen $label to SSD..."
        if ! zen_as_user rsync -aH "$link/" "$target/"; then
            echo "❌ Copy failed. Original left untouched: $link" >&2
            return 1
        fi
        if ! diff_out="$(zen_as_user rsync -rcn --itemize-changes "$link/" "$target/")" \
           || [[ -n "$diff_out" ]]; then
            echo "❌ Verification failed. Original left untouched: $link" >&2
            [[ -n "${diff_out:-}" ]] && head -n 20 <<< "$diff_out" >&2
            return 1
        fi
    fi

    backup="$link.hdd-bak-$(date +%Y%m%d-%H%M%S)"
    if ! mv -- "$link" "$backup"; then
        echo "❌ Could not rename $link" >&2
        return 1
    fi
    if ! zen_as_user ln -s "$target" "$link"; then
        echo "❌ Could not create symlink. Restoring $link" >&2
        mv -- "$backup" "$link" || true
        return 1
    fi
    ZEN_SSD_BACKUPS+=("$backup")
    echo "✅ Zen $label moved: $link -> $target"
    return 0
}

# Put ~/.config/zen and ~/.cache/zen of the desktop user on the SSD.
zen_setup_ssd() {
    local home group ssd_dir b rc=0

    ZEN_SSD_USER="$(installsh_target_user)"
    ZEN_SSD_BACKUPS=()

    if [[ -z "$ZEN_SSD_USER" || "$ZEN_SSD_USER" == "root" ]]; then
        echo "❌ SSD setup needs a desktop user. Run it with sudo from your own account." >&2
        return 1
    fi
    if ! home="$(installsh_target_home)" || [[ -z "$home" || ! -d "$home" ]]; then
        echo "❌ Home directory of $ZEN_SSD_USER not found." >&2
        return 1
    fi
    if ! group="$(id -gn "$ZEN_SSD_USER" 2>/dev/null)"; then
        echo "❌ Unknown user: $ZEN_SSD_USER" >&2
        return 1
    fi

    ssd_dir="$ZEN_SSD_BASE/$ZEN_SSD_USER"
    echo ""
    echo "💾 Zen profile/cache location: $ssd_dir"

    if ! mkdir -p "$ssd_dir" \
       || ! chown "$ZEN_SSD_USER:$group" "$ssd_dir" \
       || ! chmod 700 "$ssd_dir"; then
        echo "❌ Could not prepare $ssd_dir" >&2
        return 1
    fi
    if command -v restorecon >/dev/null 2>&1; then
        restorecon "$ZEN_SSD_BASE" "$ssd_dir" || true
    fi

    zen_link_to_ssd "$home/.config/zen" "$ssd_dir/zen-config" copy    "profile" || rc=1
    zen_link_to_ssd "$home/.cache/zen"  "$ssd_dir/zen-cache"  discard "cache"   || rc=1

    if command -v restorecon >/dev/null 2>&1; then
        restorecon -R "$ssd_dir" || true
    fi

    if ((${#ZEN_SSD_BACKUPS[@]} > 0)); then
        echo ""
        echo "🧹 Old copies kept on the previous disk. After checking Zen works, delete them with:"
        for b in "${ZEN_SSD_BACKUPS[@]}"; do
            printf "     rm -rf %q\n" "$b"
        done
    fi
    return "$rc"
}

# Keep --check output machine-readable for update-check.sh.
if [[ "$MODE" != "check" ]]; then
    echo "========================================"
    echo "      Zen Browser System Manager        "
    echo "========================================"
fi

# ---- MODE: CHECK / REGISTER (no root required) ----
if [[ "$MODE" == "check" ]]; then
    zen_check
    exit 0
fi

if [[ "$MODE" == "register" ]]; then
    zen_register
    exit 0
fi

# ---- MODE: SETUP-SSD (root) ----
if [[ "$MODE" == "setup-ssd" ]]; then
    if zen_setup_ssd; then
        exit 0
    fi
    exit 1
fi

# ---- MODE: INSTALL CHECK ----
if [[ "$MODE" == "install" ]]; then
    if [[ -x "$GLOBAL_BIN" ]] || [[ -d "$INSTALL_DIR" ]]; then
        echo "⚠️ Zen browser already installed, use flag --update to check and install new updates"
        zen_register || true
        zen_setup_ssd || echo "⚠️  SSD profile setup incomplete. Fix the issue above, then run: sudo $0 --setup-ssd"
        exit 0
    fi
    echo "🚀 Starting fresh installation..."
fi

# ---- MODE: UNINSTALL ----
if [[ "$MODE" == "uninstall" ]]; then
    echo "🛑 Starting uninstallation of Zen Browser..."

    echo ""
    echo "This uninstaller will ONLY remove the following paths:"
    echo "  - $INSTALL_DIR    (browser binaries + icon files)"
    echo "  - $GLOBAL_BIN     (launcher binary)"
    echo "  - $DESKTOP_FILE   (desktop entry)"
    echo "Your browser profile, downloads, and input files under '$INPUT_INSTALL'"
    echo "will NOT be touched. This includes the SSD profile/cache in"
    echo "'$ZEN_SSD_BASE/<user>/zen-config' and 'zen-cache' (and their ~/.config/zen, ~/.cache/zen links)."
    echo ""

    read -r -p "❓ Are you sure you want to permanently uninstall Zen Browser? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo "❌ Uninstall cancelled by user."
        exit 0
    fi

    echo ""

    # ---- SAFETY VALIDATION: refuse dangerous paths ----
    if [[ ! "$INSTALL_DIR" == /* ]] || [[ "$INSTALL_DIR" == "/" ]] \
       || [[ "$INSTALL_DIR" == *"/../"* ]] || [[ "$INSTALL_DIR" == */.. ]]; then
        echo "❌ Refusing to uninstall: '$INSTALL_DIR' is not a safe path." >&2
        exit 1
    fi

    # 1) Desktop entry (only if it clearly references Zen Browser)
    if [[ -f "$DESKTOP_FILE" ]] || [[ -L "$DESKTOP_FILE" ]]; then
        if grep -Fq "Name=Zen Browser" "$DESKTOP_FILE" 2>/dev/null \
           || grep -Fq "Exec=$GLOBAL_BIN" "$DESKTOP_FILE" 2>/dev/null; then
            rm -f -- "$DESKTOP_FILE"
            echo "✅ Removed desktop entry: $DESKTOP_FILE"
        else
            echo "⚠️  Skipped $DESKTOP_FILE: it does not reference Zen Browser."
        fi
    else
        echo "⏭️  Desktop entry not found: $DESKTOP_FILE"
    fi

    # 2) Global launcher binary (only removed if it is a symlink into $INSTALL_DIR)
    if [[ -L "$GLOBAL_BIN" ]]; then
        real_target="$(readlink -f "$GLOBAL_BIN" 2>/dev/null || readlink "$GLOBAL_BIN" 2>/dev/null || echo "")"
        if [[ -n "$real_target" && "$real_target" == "$INSTALL_DIR"/* ]]; then
            rm -f -- "$GLOBAL_BIN"
            echo "✅ Removed launcher binary: $GLOBAL_BIN"
        else
            echo "⚠️  Skipped $GLOBAL_BIN: it is not a symlink into $INSTALL_DIR (target: '$real_target')."
        fi
    elif [[ -e "$GLOBAL_BIN" ]]; then
        echo "⚠️  Skipped $GLOBAL_BIN: it is a regular file, not a symlink created by this script."
        echo "   If you wish to remove it, do so manually:  rm $GLOBAL_BIN"
    else
        echo "⏭️  Launcher binary not found: $GLOBAL_BIN"
    fi

    # 3) Install directory (contains the browser binaries and icon files)
    if [[ -e "$INSTALL_DIR" ]] || [[ -L "$INSTALL_DIR" ]]; then
        rm -rf -- "$INSTALL_DIR"
        echo "✅ Removed install directory: $INSTALL_DIR"
    else
        echo "⏭️  Install directory not found: $INSTALL_DIR"
    fi

    # 4) Refresh system caches (best effort)
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "/usr/share/applications" >/dev/null 2>&1 || true
    fi
    if [[ -d "/usr/share/icons/hicolor" ]] && command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f -t "/usr/share/icons/hicolor" >/dev/null 2>&1 || true
    fi

    # 5) Stop tracking this install in update-check
    installsh_flag_remove zen || true

    echo ""
    echo "✅ Uninstall complete. Zen Browser has been removed."
    exit 0
fi

# ---- FETCH LATEST VERSION DATA ----
echo "🔍 Checking latest release from GitHub..."
if ! zen_fetch_latest; then
    echo "❌ Error: Could not fetch release data from GitHub (${ZEN_FETCH_ERROR:-unknown})." >&2
    exit 1
fi

LATEST_VERSION="$ZEN_LATEST_TAG"
DOWNLOAD_URL="$ZEN_LATEST_URL"

# ---- MODE: UPDATE CHECK ----
if [[ "$MODE" == "update" ]]; then
    if [[ ! -x "$GLOBAL_BIN" ]]; then
        echo "❌ Zen browser is not installed yet or not found at $GLOBAL_BIN."
        echo "👉 Please run: sudo $0 --install"
        exit 1
    fi

    CURRENT_VERSION="$(zen_current_version || true)"
    CURRENT_VERSION="${CURRENT_VERSION:-unknown}"

    echo "📦 Current version: $CURRENT_VERSION"
    echo "🌟 Latest version:  $LATEST_VERSION"

    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        echo "✅ You are already up to date! No action required."
        zen_register || true
        exit 0
    fi

    if [[ "$(printf '%s\n%s\n' "$CURRENT_VERSION" "$LATEST_VERSION" | sort -V | tail -n 1)" != "$LATEST_VERSION" ]]; then
        echo "✅ Installed version is newer than the latest release. No action required."
        zen_register || true
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
TMP_DIR="$(mktemp -d /tmp/zen_installer.XXXXXX)"
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
    # Create the profile/cache links on the SSD before Zen's first start.
    zen_setup_ssd || echo "⚠️  SSD profile setup incomplete. Fix the issue above, then run: sudo $0 --setup-ssd"
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

# Keep update-check's flag in sync with the installed version.
zen_register || true
