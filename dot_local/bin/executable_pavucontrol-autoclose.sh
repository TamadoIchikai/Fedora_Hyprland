#!/usr/bin/env bash
# toggle-pavucontrol.sh — show/hide pavucontrol window in Hyprland “scratchpad”-style

APP_CLASS="pavucontrol"
APP_TITLE="Volume Control"
HYPRCTL="/usr/bin/hyprctl"

# Function: get window address by class or title
get_window_address() {
    $HYPRCTL clients -j | jq -r \
        --arg app "$APP_CLASS" --arg title "$APP_TITLE" \
        '.[] | select(.class == $app or .initialTitle == $title or .title == $title) | .address' | head -n1
}

# Function: check if window is focused
is_focused() {
    local addr="$1"
    $HYPRCTL activewindow -j | jq -r '.address' | grep -q "$addr"
}

# Try to find window
addr=$(get_window_address)

if [ -z "$addr" ]; then
    # Launch pavucontrol if not found
    pavucontrol & disown
    sleep 1.2  # allow to spawn
    addr=$(get_window_address)
    [ -z "$addr" ] && exit 0
fi

# Check if visible
visible=$($HYPRCTL clients -j | jq -r --arg addr "$addr" '.[] | select(.address == $addr) | .mapped')

if [ "$visible" == "false" ]; then
    # Show window (bring to current workspace and center)
    $HYPRCTL dispatch focuswindow address:"$addr"
    $HYPRCTL dispatch movetoworkspace current,address:"$addr"
    $HYPRCTL dispatch togglefloating address:"$addr"
    $HYPRCTL dispatch resizewindowpixel exact 700 500,address:"$addr"
    $HYPRCTL dispatch centerwindow address:"$addr"
else
    # Hide window (move to special workspace "scratch")
    $HYPRCTL dispatch movetoworkspace special:scratch,address:"$addr"
fi

# Watch focus and hide when unfocused
if [ -n "$addr" ]; then
    while true; do
        if ! is_focused "$addr"; then
            $HYPRCTL dispatch movetoworkspace special:scratch,address:"$addr"
            break
        fi
        sleep 0.3
    done
fi
