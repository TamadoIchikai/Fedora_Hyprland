#!/usr/bin/env bash
# Core system: Hyprland (pinned) + base tooling shared by later steps.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# Shared version pins (HYPRLAND_EVR, VERSIONLOCK, ...). Env vars win over the
# file defaults; see versions.env for the bump workflow.
# shellcheck source=versions.env
source "$SCRIPT_DIR/versions.env"

# --- Base tooling (later steps rely on these) ---
dnf_install \
  git wget curl unzip jq \
  gcc gcc-c++ make meson cmake ninja-build \
  vim neovim fastfetch \
  flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# --- Hyprland ecosystem ---
copr_enable lionheartp/Hyprland
dnf_install hyprlock hyprshutdown hyprland-guiutils wlsunset swaybg

# Install hyprland at the pinned EVR; fall back to latest when the COPR has
# dropped the old build (it only keeps the newest in its repodata).
if [[ -n "$HYPRLAND_EVR" ]]; then
  if ! dnf_install "hyprland-${HYPRLAND_EVR}" "hyprland-devel-${HYPRLAND_EVR}"; then
    warn "hyprland-${HYPRLAND_EVR} is no longer available in the COPR; installing the latest build instead."
    warn "Update HYPRLAND_EVR in versions.env to a current EVR (dnf list --showduplicates hyprland)."
    dnf_install hyprland hyprland-devel
  fi
else
  dnf_install hyprland hyprland-devel
fi

# Lock the pair so routine upgrades cannot break the plugin ABI.
if [[ "$VERSIONLOCK" == "1" ]]; then
  sudo dnf versionlock add hyprland hyprland-devel
  echo "🔒 hyprland + hyprland-devel locked to the installed EVR (dnf versionlock list)."
  echo "👉 To bump later: sudo dnf versionlock delete hyprland hyprland-devel"
fi

Hyprland --version | head -n1
