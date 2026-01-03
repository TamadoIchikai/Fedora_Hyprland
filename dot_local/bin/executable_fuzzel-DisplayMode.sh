#!/bin/bash

INT=eDP-1
EXT=HDMI-A-1
CONF="$HOME/.config/hypr/scripts/monitors.conf"

SEL="$(printf "󱄄  󰷜  - Extend\n󰹑  󰶐  - Internal Only\n󰶐  󰹑  - External Only\n󰹑  󰹑  - Mirror" \
  | fuzzel --dmenu -l 8 -p "Display Mode: ")"

case "$SEL" in
  *"Extend")
    hyprctl keyword monitor "$INT,1920x1080@60,0x0,1"
    hyprctl keyword monitor "$EXT,1920x1080@60,1920x0,1"

    cat > "$CONF" <<EOF
monitor=$INT,1920x1080@60,0x0,1
monitor=$EXT,1920x1080@60,1920x0,1
EOF
    ;;

  *"Internal Only")
    hyprctl keyword monitor "$INT,1920x1080@60,0x0,1"
    hyprctl keyword monitor "$EXT,disable"

    cat > "$CONF" <<EOF
monitor=$INT,1920x1080@60,0x0,1
monitor=$EXT,disable
EOF
    ;;

  *"External Only")
    hyprctl keyword monitor "$INT,disable"
    hyprctl keyword monitor "$EXT,1920x1080@60,0x0,1"

    cat > "$CONF" <<EOF
monitor=$INT,disable
monitor=$EXT,1920x1080@60,0x0,1
EOF
    ;;

  *"Mirror")
    hyprctl keyword monitor "$INT,1920x1080@60,0x0,1"
    hyprctl keyword monitor "$EXT,preferred,0x0,1,mirror,$INT"

    cat > "$CONF" <<EOF
monitor=$INT,1920x1080@60,0x0,1
monitor=$EXT,preferred,0x0,1,mirror,$INT
EOF
    ;;
esac

# reload config so persistence file is now authoritative
hyprctl reload

