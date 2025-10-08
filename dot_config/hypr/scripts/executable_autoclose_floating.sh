#!/usr/bin/env bash
# Automatically close transient floating windows like pavucontrol or blueman-manager when focus changes

apps=("org.pulseaudio.pavucontrol" "blueman-manager")

while true; do
    focused_class=$(hyprctl activewindow -j | jq -r '.class' 2>/dev/null)
    # Get all currently open matching windows
    for app in "${apps[@]}"; do
        # Count how many matching windows are open
        if hyprctl clients -j | jq -r '.[].class' | grep -q "^$app$"; then
            # If current focus is not that app, close all its windows
            if [[ "$focused_class" != "$app" ]]; then
                hyprctl dispatch killactive,class:$app >/dev/null 2>&1 || true
                hyprctl dispatch killwindow class:$app >/dev/null 2>&1 || true
                pkill -x "$app" >/dev/null 2>&1 || true
            fi
        fi
    done
    sleep 0.4  # check focus every 0.8s
done
