#!/usr/bin/env bash
# toggle-blueman.sh — toggle blueman-manager window in Hyprland scratchpad style

APP_CLASS="blueman-manager"
HYPRCTL="/usr/bin/hyprctl"

# Function: get window address
get_window_address() {
    $HYPRCTL clients -j | jq -r \
        --arg app "$APP_CLASS" \
        '.[] | select(.class == $app or .initialClass == $app) | .address' | head -n1
}

# Function: check if window is focused
is_focused() {
    local addr="$1"
    $HYPRCTL activewindow -j | jq -r '.address' | grep -q "$addr"
}

# Try to find window
addr=$(get_window_address)

if [ -z "$addr" ]; then
    # Launch Blueman if not found
    blueman-manager & disown
    sleep 1.2  # give it time to appear
    addr=$(get_window_address)
    [ -z "$addr" ] && exit 0
fi

# Toggle visibility
visible=$($HYPRCTL clients -j | jq -r --arg addr "$addr" '.[] | select(.address == $addr) | .mapped')

if [ "$visible" == "false" ]; then
    # Show window (move to current workspace, center, float)
    $HYPRCTL dispatch focuswindow address:"$addr"
    $HYPRCTL dispatch movetoworkspace current,address:"$addr"
    $HYPRCTL dispatch togglefloating address:"$addr"
    $HYPRCTL dispatch resizewindowpixel exact 600 500,address:"$addr"
    $HYPRCTL dispatch centerwindow address:"$addr"
else
    # Hide by moving to special workspace "scratch"
    $HYPRCTL dispatch movetoworkspace special:scratch,address:"$addr"
fi

# Monitor focus loss and hide again
if [ -n "$addr" ]; then
    while true; do
        if ! is_focused "$addr"; then
            $HYPRCTL dispatch movetoworkspace special:scratch,address:"$addr"
            break
        fi
        sleep 0.3
    done
fi

