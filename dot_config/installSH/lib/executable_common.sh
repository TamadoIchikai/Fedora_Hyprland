#!/usr/bin/env bash
#
# common.sh - shared helpers for installSH step scripts.
#
# Usage (from a script in installSH/ or installSH/optional/):
#   source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"      # top level
#   source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"   # optional/
#
# Provides: INSTALLSH_DIR, colors, info/ok/warn/die, require_cmd,
# dnf_install, copr_enable, flatpak_install, plus everything in state.sh
# (installsh_target_user, installsh_target_home, flag helpers).

[[ -n "${_INSTALLSH_COMMON_LOADED:-}" ]] && return 0
_INSTALLSH_COMMON_LOADED=1

INSTALLSH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export INSTALLSH_DIR

# shellcheck source=state.sh
source "$INSTALLSH_DIR/lib/state.sh"

# Colors (install.sh exports these too; defaults let scripts run standalone).
: "${CYAN:=\033[0;36m}"
: "${GREEN:=\033[0;32m}"
: "${YELLOW:=\033[1;33m}"
: "${RED:=\033[0;31m}"
: "${NC:=\033[0m}"

info() { echo -e "${CYAN}➡️  $*${NC}"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}" >&2; }
die()  { echo -e "${RED}❌ $*${NC}" >&2; exit 1; }

require_cmd() {
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || die "Required command not found: $c"
    done
}

# dnf_install pkg... - install packages (no-op for already installed ones).
dnf_install() {
    sudo dnf install -y "$@"
}

# copr_enable owner/project... - enable COPR repos (idempotent).
copr_enable() {
    local repo
    for repo in "$@"; do
        sudo dnf copr enable -y "$repo"
    done
}

# flatpak_install app-id... - install from flathub (adds the remote if missing).
flatpak_install() {
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install -y --noninteractive flathub "$@"
}
