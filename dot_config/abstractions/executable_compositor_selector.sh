#!/usr/bin/env bash
#
# compositor_selector.sh — print the backend directory for the current WM.
#
# Prefers WM_CURR (set by ../../wm.sh), falls back to DESKTOP_COMPOSITOR.

_wm="${WM_CURR:-${DESKTOP_COMPOSITOR:-}}"

case "$_wm" in
    hyprland)
        echo "${WM_API_DIR:-$HOME/.config/abstractions}/hyprland"
        ;;

    mangowc)
        echo "${WM_API_DIR:-$HOME/.config/abstractions}/mangowc"
        ;;

    *)
        echo "Unsupported compositor: ${_wm:-<unset>}" >&2
        exit 1
        ;;
esac
