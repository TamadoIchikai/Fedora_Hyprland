#!/usr/bin/env bash
source "$HOME/.config/abstractions/wm.sh"

address=$1

# https://api.gtkd.org/gdk.c.types.GdkEventButton.button.html
button=$2

if [ "$button" -eq 1 ]; then
    # Left click: focus window
    WM_window_focus "$address"
elif [ "$button" -eq 2 ]; then
    # Middle click: close window
    WM_window_close "$address"
fi
