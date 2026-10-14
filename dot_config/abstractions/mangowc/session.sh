#!/usr/bin/env bash
#
# mangowc/session.sh — MangoWC session control.

WM_reload() {
    mmsg dispatch reload_config >/dev/null
}

WM_exit() {
    mmsg dispatch quit >/dev/null
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
