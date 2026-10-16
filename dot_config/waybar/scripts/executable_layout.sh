#!/usr/bin/env bash

# Displays the active Hyprland tiling layout as a Nerd Font icon.
# - never prints errors
# - always exits 0

# If hyprctl/jq aren't available, just show the default icon (don't error).
command -v hyprctl >/dev/null 2>&1 || { printf '%s\n' "󰕮"; exit 0; }
command -v jq >/dev/null 2>&1 || { printf '%s\n' "󰕮"; exit 0; }

layout=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str // empty')

case "$layout" in
    dwindle)   icon="󰕮" ;;  # md-view-dashboard   U+F056E
    scrolling) icon="󰕬" ;;  # md-view-carousel    U+F056C
    *)         icon="󰕮" ;;  # default
esac

printf '%s\n' "$icon"
exit 0
