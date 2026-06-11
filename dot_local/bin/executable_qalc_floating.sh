#!/usr/bin/env bash
set -euo pipefail

# Floating centered Qalculate popup on Hyprland Lua config

TERMINAL="foot"
WINDOW_TITLE="QalcPopup"
FONT_SIZE="13"

# Toggle behavior: close if already running
if pgrep -u "$USER" -f "$TERMINAL .*--title[ =]$WINDOW_TITLE" >/dev/null; then
    pkill -u "$USER" -f "$TERMINAL .*--title[ =]$WINDOW_TITLE"
    exit 0
fi

CMD="$TERMINAL --title $WINDOW_TITLE \
--override \"font=JetBrainsMono Nerd Font:size=$FONT_SIZE\" \
bash -lc 'clear; echo \"Qalculate ready.\"; exec qalc -s \"autocalc on\"'"

hyprctl dispatch "hl.dsp.exec_cmd([[$CMD]], { float = true, center = true, size = { '(monitor_w*0.65)', '(monitor_h*0.60)' } })"
