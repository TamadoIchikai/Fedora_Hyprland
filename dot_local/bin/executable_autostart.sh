#!/usr/bin/env bash
set -euo pipefail

BG_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-autostart.log"
TIMER_FAST_TO_MEDIUM=2
TIMER_FAST_TO_COMPLEX=4
mkdir -p "$(dirname "$BG_LOG")"

run_once() {
    local pattern="$1"
    shift

    if pgrep -u "$USER" -f "$pattern" >/dev/null 2>&1; then
        return 0
    fi

    "$@" >>"$BG_LOG" 2>&1 &
}

hypr_exec_ws() {
    local workspace="$1"
    shift

    local cmd="$*"

    hyprctl dispatch "hl.dsp.exec_cmd([[$cmd]], { workspace = [[$workspace silent]] })" \
        >>"$BG_LOG" 2>&1 || true
}

fast_startup() {
    # First startup: start immediately after Hyprland starts
    run_once "waybar" waybar
    run_once "fcitx5" fcitx5 -d
    run_once "wl-paste --watch cliphist store" wl-paste --watch cliphist store
    run_once "hyprsunset" hyprsunset
    run_once "swaybg" swaybg -i "$HOME/.config/screenshots/background.png" -m fill
    run_once "move-on-unfocus.sh" "$HOME/.config/waybar/scripts/move-on-unfocus.sh"
}

medium_startup() {
    hypr_exec_ws "11" "pavucontrol"
    hypr_exec_ws "11" "blueman-manager"
    hypr_exec_ws "11" "LocalSend.AppImage"
    hypr_exec_ws "11" "thunar -w"

    # KeePassXC is delayed into the medium phase so Waybar tray has time to exist
    run_once "keepassxc" keepassxc --minimized
}

complex_startup() {
    systemctl --user enable opentabletdriver.service --now >>"$BG_LOG" 2>&1 || true

    hypr_exec_ws "1" "Obsidian.AppImage"
    hypr_exec_ws "2" "vivaldi-stable"
    hypr_exec_ws "10" "flatpak run io.github.mpc_qt.mpc-qt"
}

# -------------------------
# Startup sequence
# -------------------------

fast_startup

(
    sleep "$TIMER_FAST_TO_MEDIUM"
    medium_startup
) &

(
    sleep "$TIMER_FAST_TO_COMPLEX"
    complex_startup
) &
