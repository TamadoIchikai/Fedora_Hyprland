#!/usr/bin/env bash
set -euo pipefail

TERMINAL="foot"
WINDOW_TITLE="AutostartTestPopup"
GEOM_W="0.55"
GEOM_H="0.60"

BG_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-autostart.log"

TIMER_FAST_TO_MEDIUM=3
TIMER_FAST_TO_COMPLEX=5
AUTO_CLOSE_AFTER=5

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUTOSTART_SCRIPT="$SCRIPT_DIR/autostart.sh"

mkdir -p "$(dirname "$BG_LOG")"

if ! command -v "$TERMINAL" >/dev/null 2>&1; then
    echo "ERROR: terminal '$TERMINAL' not found"
    exit 1
fi

if ! command -v hyprctl >/dev/null 2>&1; then
    echo "ERROR: hyprctl not found"
    exit 1
fi

if [[ ! -x "$AUTOSTART_SCRIPT" ]]; then
    echo "ERROR: autostart script is not executable:"
    echo "       $AUTOSTART_SCRIPT"
    echo
    echo "Run:"
    echo "chmod +x '$AUTOSTART_SCRIPT'"
    exit 1
fi

CMD="$(
    printf '%q ' \
        env \
        "BG_LOG=$BG_LOG" \
        "TIMER_FAST_TO_MEDIUM=$TIMER_FAST_TO_MEDIUM" \
        "TIMER_FAST_TO_COMPLEX=$TIMER_FAST_TO_COMPLEX" \
        "AUTO_CLOSE_AFTER=$AUTO_CLOSE_AFTER" \
        "$TERMINAL" \
        --title "$WINDOW_TITLE" \
        bash "$AUTOSTART_SCRIPT"
)"

hyprctl dispatch "hl.dsp.exec_cmd([[$CMD]], {
    float = true,
    center = true,
    size = { '(monitor_w*$GEOM_W)', '(monitor_h*$GEOM_H)' }
})"
