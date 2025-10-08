#!/usr/bin/env bash
# Floating centered Qalculate popup on Hyprland with larger font

TERMINAL="foot"
WINDOW_TITLE="QalcPopup"
GEOM="40% 50%"
FONT_SIZE="13"  # change this to adjust size

# Toggle behavior: close if already running
if pgrep -f "qalc.*--title $WINDOW_TITLE" >/dev/null; then
    pkill -f "qalc.*--title $WINDOW_TITLE"
    exit 0
fi

# Launch with larger font override
hyprctl dispatch exec "[float;center;size $GEOM;title $WINDOW_TITLE] \
$TERMINAL --title $WINDOW_TITLE \
--override font='JetBrainsMono Nerd Font:size=$FONT_SIZE' \
bash -c '
clear;
echo \"Qalculate ready.\";
qalc
'"

