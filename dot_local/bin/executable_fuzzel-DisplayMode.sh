#!/bin/bash

# Read variables from hyprland environment
LAPTOP="${LAPTOP_OUTPUT}"
EXTERNAL="${EXTERNAL_OUTPUT}"
LAPTOP_MODE="${LAPTOP_MODE}"
EXTERNAL_MODE="${EXTERNAL_MODE}"
LAPTOP_POS="${LAPTOP_POS}"
EXTERNAL_POS_EXTEND="${EXTERNAL_POS_EXTEND}"
EXTERNAL_POS_MIRROR="${EXTERNAL_POS_MIRROR}"
LAPTOP_SCALE="${LAPTOP_SCALE}"
EXTERNAL_SCALE="${EXTERNAL_SCALE}"

SELECTION="$(printf "󰍹  - Extend (Dual Monitor)\n󰌢  - Internal Screen Only\n󰍺  - External Screen Only" | fuzzel --dmenu -l 4 -p "Display Mode:  ")"

case $SELECTION in
    *"Extend"*)
        hyprctl keyword monitor "$LAPTOP,$LAPTOP_MODE,$LAPTOP_POS,$LAPTOP_SCALE"
        hyprctl keyword monitor "$EXTERNAL,$EXTERNAL_MODE,$EXTERNAL_POS_EXTEND,$EXTERNAL_SCALE"
        notify-send "Display Mode" "Extended to both displays" -i video-display;;
    *"Internal Screen Only"*)
        hyprctl keyword monitor "$LAPTOP,$LAPTOP_MODE,$LAPTOP_POS,$LAPTOP_SCALE"
        hyprctl keyword monitor "$EXTERNAL,disable"
        notify-send "Display Mode" "Internal screen only" -i video-display;;
    *"External Screen Only"*)
        hyprctl keyword monitor "$LAPTOP,disable"
        hyprctl keyword monitor "$EXTERNAL,$EXTERNAL_MODE,$LAPTOP_POS,$EXTERNAL_SCALE"
        notify-send "Display Mode" "External screen only" -i video-display;;
esac
