#!/usr/bin/env bash
#
# niri/session.sh — niri session control.

WM_reload() {
    niri msg action load-config-file >/dev/null
}

WM_exit() {
    niri msg action quit --skip-confirmation >/dev/null
}

WM_lock() {
    if WM_have swaylock; then
        swaylock
    elif WM_have hyprlock; then
        hyprlock
    else
        WM_err "WM_lock: no screen locker found (swaylock/hyprlock)"
        return 1
    fi
}
