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
