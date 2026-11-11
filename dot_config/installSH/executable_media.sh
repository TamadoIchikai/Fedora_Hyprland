#!/usr/bin/env bash
# Bar, notifications, audio/bluetooth controls and media playback.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

copr_enable erikreider/SwayNotificationCenter
dnf_install waybar SwayNotificationCenter blueman pavucontrol zenity mpv mpv-mpris playerctl
