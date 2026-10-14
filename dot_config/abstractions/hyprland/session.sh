#!/usr/bin/env bash
#
# hyprland/session.sh — Hyprland session control.

WM_reload() {
    hyprctl reload >/dev/null
}

WM_exit() {
    hyprctl dispatch "hl.dsp.exit()" >/dev/null
}

WM_lock() {
    if WM_have hyprlock; then
        hyprlock
    else
        WM_err "WM_lock: hyprlock not found"
        return 1
    fi
}
