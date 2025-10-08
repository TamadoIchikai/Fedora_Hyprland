
#!/usr/bin/env bash
# Floating centered Qalculate popup on Hyprland

TERMINAL="foot"                # change to alacritty, kitty, etc. if you like
WINDOW_TITLE="QalcPopup"       # used for window rules
GEOM="60% 50%"                 # width x height ratio

# Detect if already running, to make it togglable
if pgrep -f "qalc.*--title $WINDOW_TITLE" >/dev/null; then
    pkill -f "qalc.*--title $WINDOW_TITLE"
    exit 0
fi

# Launch floating centered terminal running qalc
hyprctl dispatch exec "[float;center;size $GEOM;title $WINDOW_TITLE] $TERMINAL --title $WINDOW_TITLE bash -c '
clear; 
echo \"Qalculate ready.\"; 
qalc
'"

