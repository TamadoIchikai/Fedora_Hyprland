#!/usr/bin/env bash
# CLI + Wayland desktop tools (foot is needed by file_manager.sh later).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

copr_enable dejan/lazygit

dnf_install \
  foot fuzzel wofi \
  fzf zoxide ripgrep gawk socat btop duf gdu lazygit trash-cli qalculate \
  restic rclone fuse fuse-libs \
  wl-clipboard cliphist wtype setxkbmap swappy swayimg ImageMagick \
  nm-connection-editor \
  xournalpp lua-lgi

# resticprofile: install into ~/.local/bin (the upstream installer defaults to ./bin).
mkdir -p "$HOME/.local/bin"
curl -sfL https://raw.githubusercontent.com/creativeprojects/resticprofile/master/install.sh \
  | sh -s -- -b "$HOME/.local/bin"
