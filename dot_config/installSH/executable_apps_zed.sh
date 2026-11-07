#!/usr/bin/env bash

# ============================================================
# Zed Editor Installation & Configuration Setup
#
# Fedora / Linux
#
# Shared Windows + Fedora configuration:
#
#   /mnt/sda2/Customization/Zed/
#   └── zed_configs/
#       ├── <Zed config files>
#       └── skills/
#
# Linux:
#
#   ~/.config/zed  -> /mnt/sda2/Customization/Zed/zed_configs
#   ~/.agents/skills -> /mnt/sda2/Customization/Zed/zed_configs/skills
#
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/state.sh
source "$SCRIPT_DIR/lib/state.sh"

# Optional GitHub token support (avoids anonymous API rate limits). The helper
# checks exported GITHUB_TOKEN/GH_TOKEN first, then token files, so login-time
# checks do not depend on shell exports.
GITHUB_TOKEN="$(installsh_github_token 2>/dev/null || true)"
export GITHUB_TOKEN

# ============================================================
# Argument parsing
# ============================================================

MODE="install"

case "${1:-}" in
    ""|--install)
        MODE="install"
        ;;
    --check)
        MODE="check"
        ;;
    --update)
        MODE="update"
        ;;
    --register)
        MODE="register"
        ;;
    -h|--help)
        cat <<'EOF'
Usage:
  apps_zed.sh                 Install Zed and configure symlinks
  apps_zed.sh --install       Same as above
  apps_zed.sh --check         Show installed/latest version (no changes)
  apps_zed.sh --update        Run the official installer and refresh state
  apps_zed.sh --register      Write update-checker flag for an existing install
  apps_zed.sh --help          Show this help
EOF
        exit 0
        ;;
    *)
        printf '❌ Unknown option: %s\n' "$1" >&2
        exit 1
        ;;
esac

# ============================================================
# Configuration
# ============================================================

COMMON_ZED_DIR="/mnt/sda2/Customization/Zed"
COMMON_CONFIG_DIR="${COMMON_ZED_DIR}/zed_configs"
COMMON_SKILLS_DIR="${COMMON_ZED_DIR}/skills"

ZED_CONFIG_DIR="${HOME}/.config/zed"
AGENT_SKILLS_DIR="${HOME}/.agents/skills"

# ============================================================
# Colors / output helpers
# ============================================================

info() {
    printf '\n[INFO] %s\n' "$*"
}

success() {
    printf '[ OK ] %s\n' "$*"
}

warning() {
    printf '[WARN] %s\n' "$*" >&2
}

error() {
    printf '[ERROR] %s\n' "$*" >&2
}

# ============================================================
# Check / update helpers
# ============================================================

if [[ -d "${HOME}/.local/bin" ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
fi

zed_current_version() {
    if command -v zed >/dev/null 2>&1; then
        zed --version 2>/dev/null | awk 'NR == 1 { print $2 }'
    fi
}

zed_latest_version() {
    local response
    local -a auth=()

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    response="$(curl -fsSL --connect-timeout 5 --max-time 15 \
        "${auth[@]}" \
        -H "Accept: application/vnd.github+json" \
        https://api.github.com/repos/zed-industries/zed/releases/latest \
        2>/dev/null || true)"

    [[ -n "${response}" ]] || return 1

    jq -r '.tag_name // empty' <<< "${response}" 2>/dev/null | sed 's/^v//'
}

if [[ "${MODE}" == "check" ]]; then
    current_version="$(zed_current_version || true)"
    latest_version="$(zed_latest_version || true)"
    state="error"
    detail=""

    if [[ -z "${current_version}" ]]; then
        detail="zed not installed"
    elif [[ -z "${latest_version}" ]]; then
        detail="latest version unavailable"
    elif [[ "${current_version}" == "${latest_version}" ]]; then
        state="current"
    elif [[ "$(printf '%s\n%s\n' "${current_version}" "${latest_version}" | sort -V | tail -n 1)" == "${latest_version}" ]]; then
        state="update"
    else
        state="newer"
        detail="installed version is newer"
    fi

    printf 'zed\t%s\t%s\t%s\t%s\n' \
        "${current_version:-unknown}" \
        "${latest_version:-unknown}" \
        "${state}" \
        "${detail}"

    [[ "${state}" != "error" ]] || exit 1
    exit 0
fi

if [[ "${MODE}" == "update" ]]; then
    info "Updating Zed Editor..."

    if ! curl -f --connect-timeout 10 --max-time 60 https://zed.dev/install.sh | sh; then
        error "Zed update failed."
        exit 1
    fi

    export PATH="${HOME}/.local/bin:${PATH}"

    if ! command -v zed >/dev/null 2>&1; then
        error "Zed update completed, but 'zed' was not found in PATH."
        exit 1
    fi

    current_version="$(zed_current_version || true)"

    installsh_flag_write "zed" \
        "name=Zed" \
        "kind=zed" \
        "source=apps_zed.sh" \
        "binary=$(command -v zed)" \
        "installed_version=${current_version:-unknown}" \
        "updated_at=$(date -Is)" || true

    success "Zed updated to ${current_version:-unknown}."
    exit 0
fi

if [[ "${MODE}" == "register" ]]; then
    current_version="$(zed_current_version || true)"

    if [[ -z "${current_version}" ]]; then
        error "Zed is not installed; cannot register it."
        exit 1
    fi

    installsh_flag_write "zed" \
        "name=Zed" \
        "kind=zed" \
        "source=apps_zed.sh" \
        "binary=$(command -v zed)" \
        "installed_version=${current_version}" \
        "updated_at=$(date -Is)" || true

    success "Registered Zed ${current_version}."
    exit 0
fi

# ============================================================
# Check dependencies
# ============================================================

info "Checking required commands..."

for command in curl mountpoint mv mkdir ln readlink; do
    if ! command -v "$command" >/dev/null 2>&1; then
        error "Required command not found: ${command}"
        exit 1
    fi
done

success "Required commands are available."

# ============================================================
# Check external drive
# ============================================================

info "Checking external drive..."

if ! mountpoint -q /mnt/sda2; then
    error "/mnt/sda2 is not mounted."
    error "Mount the drive first, then run this script again."
    exit 1
fi

success "/mnt/sda2 is mounted."

# ============================================================
# Check common directories
# ============================================================

info "Checking shared Zed directories..."

if [[ ! -d "${COMMON_ZED_DIR}" ]]; then
    error "Common Zed directory does not exist:"
    error "  ${COMMON_ZED_DIR}"
    exit 1
fi

if [[ ! -d "${COMMON_CONFIG_DIR}" ]]; then
    error "Zed configuration directory does not exist:"
    error "  ${COMMON_CONFIG_DIR}"
    exit 1
fi

if [[ ! -d "${COMMON_SKILLS_DIR}" ]]; then
    error "Agent skills directory does not exist:"
    error "  ${COMMON_SKILLS_DIR}"
    exit 1
fi

success "Shared Zed directories are available."

# ============================================================
# Install Zed
# ============================================================

info "Installing Zed Editor..."

if command -v zed >/dev/null 2>&1; then
    success "Zed is already installed."
else
    info "Running official Zed installer..."

    curl -f https://zed.dev/install.sh | sh

    success "Zed installation completed."
fi

# ============================================================
# Refresh PATH
# ============================================================
#
# The Zed installer normally places the binary in ~/.local/bin.
# The current shell may not have that directory in PATH yet.
#
# ============================================================

if [[ -d "${HOME}/.local/bin" ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
fi

if command -v zed >/dev/null 2>&1; then
    success "Zed executable found: $(command -v zed)"
else
    warning "Zed was installed, but 'zed' is not currently in PATH."
    warning "You may need to restart your shell."
fi

# ============================================================
# Backup existing destination
# ============================================================

backup_existing() {
    local destination="$1"

    # Nothing exists.
    if [[ ! -e "${destination}" && ! -L "${destination}" ]]; then
        return 0
    fi

    # Already a symlink. Remove ONLY the symlink.
    if [[ -L "${destination}" ]]; then
        info "Removing existing symbolic link:"
        info "  ${destination}"

        rm -f -- "${destination}"

        success "Existing symbolic link removed."
        return 0
    fi

    # Existing real file/directory.
    #
    # NEVER delete it automatically.
    # Move it to a timestamped backup instead.
    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"

    local backup="${destination}.backup-${timestamp}"

    info "Existing real path detected:"
    info "  ${destination}"

    warning "It will NOT be deleted."
    info "Moving it to:"
    info "  ${backup}"

    mv -- "${destination}" "${backup}"

    success "Existing path backed up."
}

# ============================================================
# Create symbolic link
# ============================================================

create_symlink() {
    local source="$1"
    local destination="$2"

    info "Setting up symbolic link:"
    info "  ${destination}"
    info "    -> ${source}"

    # --------------------------------------------------------
    # If destination is already the correct symlink, do nothing.
    # --------------------------------------------------------

    if [[ -L "${destination}" ]]; then
        local current_target

        current_target="$(readlink -- "${destination}")"

        if [[ "${current_target}" == "${source}" ]]; then
            success "Correct symbolic link already exists."
            return 0
        fi

        info "Existing symbolic link points somewhere else."
    fi

    # --------------------------------------------------------
    # Remove/backup existing destination safely.
    # --------------------------------------------------------

    backup_existing "${destination}"

    # --------------------------------------------------------
    # Ensure parent directory exists.
    # --------------------------------------------------------

    mkdir -p -- "$(dirname -- "${destination}")"

    # --------------------------------------------------------
    # Create symlink.
    # --------------------------------------------------------

    ln -s -- "${source}" "${destination}"

    # --------------------------------------------------------
    # Verify symlink.
    # --------------------------------------------------------

    if [[ ! -L "${destination}" ]]; then
        error "Failed to create symbolic link:"
        error "  ${destination}"
        exit 1
    fi

    local actual_target
    actual_target="$(readlink -- "${destination}")"

    if [[ "${actual_target}" != "${source}" ]]; then
        error "Symbolic link verification failed."
        error "Expected:"
        error "  ${source}"
        error "Got:"
        error "  ${actual_target}"
        exit 1
    fi

    success "Symbolic link created successfully."
}

# ============================================================
# Zed configuration
# ============================================================

info "Configuring Zed..."

create_symlink \
    "${COMMON_CONFIG_DIR}" \
    "${ZED_CONFIG_DIR}"

# ============================================================
# Agent skills
# ============================================================

info "Configuring Zed Agent Skills..."

create_symlink \
    "${COMMON_SKILLS_DIR}" \
    "${AGENT_SKILLS_DIR}"

# ============================================================
# Final verification
# ============================================================

info "Verifying installation..."

echo
echo "Zed configuration:"
printf '  %s -> %s\n' \
    "${ZED_CONFIG_DIR}" \
    "$(readlink -- "${ZED_CONFIG_DIR}")"

echo
echo "Agent skills:"
printf '  %s -> %s\n' \
    "${AGENT_SKILLS_DIR}" \
    "$(readlink -- "${AGENT_SKILLS_DIR}")"

echo

if [[ -L "${ZED_CONFIG_DIR}" ]] &&
   [[ "$(readlink -- "${ZED_CONFIG_DIR}")" == "${COMMON_CONFIG_DIR}" ]]; then
    success "Zed configuration link verified."
else
    error "Zed configuration link verification failed."
    exit 1
fi

if [[ -L "${AGENT_SKILLS_DIR}" ]] &&
   [[ "$(readlink -- "${AGENT_SKILLS_DIR}")" == "${COMMON_SKILLS_DIR}" ]]; then
    success "Agent skills link verified."
else
    error "Agent skills link verification failed."
    exit 1
fi

# ============================================================
# Register installation for the login update checker
# ============================================================

zed_installed_version="$(zed_current_version || true)"

installsh_flag_write "zed" \
    "name=Zed" \
    "kind=zed" \
    "source=apps_zed.sh" \
    "binary=$(command -v zed 2>/dev/null || true)" \
    "installed_version=${zed_installed_version:-unknown}" \
    "updated_at=$(date -Is)" || true

# ============================================================
# Done
# ============================================================

echo
success "Zed setup completed successfully."

echo
echo "Shared configuration:"
echo "  ${COMMON_CONFIG_DIR}"

echo
echo "Linux Zed configuration:"
echo "  ${ZED_CONFIG_DIR}"
echo "    -> ${COMMON_CONFIG_DIR}"

echo
echo "Shared agent skills:"
echo "  ${COMMON_SKILLS_DIR}"

echo
echo "Linux agent skills:"
echo "  ${AGENT_SKILLS_DIR}"
echo "    -> ${COMMON_SKILLS_DIR}"

echo
echo "You can now start Zed with:"
echo "  zed"
