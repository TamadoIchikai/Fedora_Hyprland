#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.config/abstractions/wm.sh"

TERMINAL="foot"
WINDOW_TITLE="AutostartTestPopup"
GEOM_W="0.55"
GEOM_H="0.60"

BG_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-autostart.log"

TIMER_FAST_TO_MEDIUM=3
TIMER_FAST_TO_COMPLEX=6
AUTO_CLOSE_AFTER=5

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUTOSTART_SCRIPT="$SCRIPT_DIR/autostart.sh"

mkdir -p "$(dirname "$BG_LOG")"

if ! command -v "$TERMINAL" >/dev/null 2>&1; then
    echo "ERROR: terminal '$TERMINAL' not found"
    exit 1
fi

if [ -z "${WM_CURR:-}" ]; then
    echo "ERROR: no supported compositor detected"
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

WM_exec_floating "$CMD" true "$GEOM_W" "$GEOM_H"
