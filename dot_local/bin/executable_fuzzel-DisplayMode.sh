#!/bin/bash

INT=eDP-1
EXT=HDMI-A-1

SEL="$(printf "1 - Extend\n2 - Internal Only\n3 - External Only\n4 - Mirror" \
  | fuzzel --dmenu -l 8 -p "Display Mode: ")"

case "$SEL" in
  *"Extend")
    hyprctl keyword monitor "$INT,1920x1080@60,0x0,1"
    hyprctl keyword monitor "$EXT,1920x1080@60,1920x0,1"
    ;;

  *"Internal Only")
    hyprctl keyword monitor "$INT,1920x1080@60,0x0,1"
    hyprctl keyword monitor "$EXT,disable"
    ;;

  *"External Only")
    hyprctl keyword monitor "$INT,disable"
    hyprctl keyword monitor "$EXT,1920x1080@60,0x0,1"
    ;;

  *"Mirror")
    # EXT mirrors INT
    hyprctl keyword monitor "$INT,1920x1080@60,0x0,1"
    hyprctl keyword monitor "$EXT,preferred,0x0,1,mirror,$INT"
    ;;
esac

