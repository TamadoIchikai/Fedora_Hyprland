#!/usr/bin/env bash
#
# wm.sh — compositor-agnostic window-management API.
#
# Source this file to load the API for the running compositor:
#     source ~/.config/abstractions/wm.sh
#
# After loading, all WM_* functions are available in the current shell.
# Safe to source repeatedly.

if [ -n "${WM_API_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
WM_API_LOADED=1

: "${WM_API_DIR:=$HOME/.config/abstractions}"
# Note: WM_API_DIR and WM_CURR decide which files are sourced/executed below.
# They are treated as trusted (user-session) inputs, not attacker-controlled.

# Shared helpers (WM_err, WM_have, WM_require, ...).
source "$WM_API_DIR/common.sh" 2>/dev/null || true

# Runtime compositor detection. Priority:
#   1. WM_CURR          (explicit override)
#   2. XDG_CURRENT_DESKTOP
#   3. instance-signature / binary probe
WM_detect() {
    if [ -n "${WM_CURR:-}" ]; then
        case "$WM_CURR" in
            hyprland|mangowc|niri) printf '%s' "$WM_CURR"; return 0 ;;
        esac
    fi

    case "${XDG_CURRENT_DESKTOP:-}" in
        *Mango*|*mango*)     printf 'mangowc';  return 0 ;;
        *Hyprland*|*hyprland*) printf 'hyprland'; return 0 ;;
        *Niri*|*niri*)       printf 'niri';     return 0 ;;
    esac

    if [ -n "${MANGO_INSTANCE_SIGNATURE:-}" ] || WM_have mmsg; then
        printf 'mangowc'; return 0
    fi
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || WM_have hyprctl; then
        printf 'hyprland'; return 0
    fi
    if [ -n "${NIRI_SOCKET:-}" ] || WM_have niri; then
        printf 'niri'; return 0
    fi

    return 1
}

if [ -z "${WM_CURR:-}" ]; then
    WM_CURR="$(WM_detect)" || WM_CURR=""
fi
export WM_CURR

# Load backend implementations for the detected compositor.
WM_API_BACKEND="$(WM_API_DIR="$WM_API_DIR" "$WM_API_DIR/compositor_selector.sh" 2>/dev/null)" || WM_API_BACKEND=""

if [ -n "$WM_API_BACKEND" ] && [ -d "$WM_API_BACKEND" ]; then
    # Source a fixed allowlist rather than globbing every *.sh in the dir, so
    # a stray or planted file can't be executed in every new shell.
    for _wm_part in exec monitor session window workspace; do
        _wm_file="$WM_API_BACKEND/$_wm_part.sh"
        [ -f "$_wm_file" ] || { WM_err "missing backend file: $_wm_part.sh"; continue; }
        source "$_wm_file"
    done
    unset _wm_file _wm_part
else
    WM_err "no backend loaded (WM_CURR='${WM_CURR:-<unset>}')"
fi
unset WM_API_BACKEND

# Raw escape hatch: run a backend-native command verbatim.
WM_dispatch() {
    case "$WM_CURR" in
        hyprland) hyprctl dispatch "$@" ;;
        mangowc)  mmsg dispatch "$@" ;;
        niri)     niri msg "$@" ;;
        *) return 1 ;;
    esac
}
