#!/usr/bin/env bash
set -euo pipefail

sudo dnf copr enable -y dejan/lazygit
sudo dnf install -y foot restic rclone fuzzel fzf zoxide cliphist fuse fuse-libs qalculate setxkbmap trash-cli swappy btop lazygit duf gdu swayimg xournalpp lua-lgi nm-connection-editor wtype wofi ripgrep ImageMagick gawk wl-clipboard
curl -sfL https://raw.githubusercontent.com/creativeprojects/resticprofile/master/install.sh | sh
