#!/usr/bin/env bash
# Automatically adjust fuzzel font size depending on which monitor (laptop vs external) you're on

# Get the focused monitor name from Hyprland
MONITOR=$(hyprctl monitors -j | jq -r '.[] | select(.focused==true).name')

# Define your laptop monitor name (check with `hyprctl monitors`)
LAPTOP_MONITOR="eDP-1"

# Choose font sizes
FONT_LAPTOP="JetBrainsMono Nerd Font:size=13"
FONT_EXTERNAL="JetBrainsMono Nerd Font:size=13"

# Select font depending on monitor
if [ "$MONITOR" = "$LAPTOP_MONITOR" ]; then
    FONT="$FONT_LAPTOP"
else
    FONT="$FONT_EXTERNAL"
fi

# Launch fuzzel with chosen font
fuzzel --font "$FONT"

