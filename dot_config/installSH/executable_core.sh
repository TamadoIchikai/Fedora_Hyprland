#!/usr/bin/env bash
set -euo pipefail

# Shared version pins (HYPRLAND_EVR, VERSIONLOCK, ...). Env vars win over the
# file defaults; see versions.env for the bump workflow.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "$SCRIPT_DIR/versions.env"

sudo dnf copr enable -y lionheartp/Hyprland
sudo dnf install -y hyprlock wlsunset swaybg hyprland-guiutils vim neovim fastfetch meson cmake flatpak

# Install hyprland at the pinned EVR; fall back to latest when the COPR has
# dropped the old build (it only keeps the newest in its repodata).
if [[ -n "$HYPRLAND_EVR" ]]; then
  if ! sudo dnf install -y "hyprland-${HYPRLAND_EVR}" "hyprland-devel-${HYPRLAND_EVR}"; then
    echo "⚠️  hyprland-${HYPRLAND_EVR} is no longer available in the COPR; installing the latest build instead." >&2
    echo "👉 Update HYPRLAND_EVR in versions.env to a current EVR (dnf list --showduplicates hyprland)." >&2
    sudo dnf install -y hyprland hyprland-devel
  fi
else
  sudo dnf install -y hyprland hyprland-devel
fi

# Lock the pair so routine upgrades cannot break the plugin ABI.
if [[ "$VERSIONLOCK" == "1" ]]; then
  sudo dnf versionlock add hyprland hyprland-devel
  echo "🔒 hyprland + hyprland-devel locked to the installed EVR (dnf versionlock list)."
  echo "👉 To bump later: sudo dnf versionlock delete hyprland hyprland-devel"
fi

Hyprland --version | head -n1
