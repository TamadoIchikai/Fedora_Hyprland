#!/usr/bin/env bash
set -euo pipefail

sudo dnf copr enable -y dejan/lazygit
sudo dnf install -y foot fuzzel fzf zoxide cliphist fuse fuse-libs qalculate setxkbmap trash-cli swappy btop lazygit duf gdu swayimg xournalpp lua-lgi nm-connection-editor wtype wofi ripgrep ImageMagick gawk wl-clipboard
