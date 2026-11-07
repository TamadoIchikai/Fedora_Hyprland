#!/usr/bin/env bash
#
# update-check-popup.sh - visible fallback for update-check.sh.
#
# Opened in a floating foot window only when notify-send fails. The caller
# passes UPDATE_CHECK_CACHE_DIR and launches this through WM_exec_floating.

set -euo pipefail

CACHE_DIR="${UPDATE_CHECK_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/update-check}"
STATUS_FILE="$CACHE_DIR/status.env"
REPORT_TXT="$CACHE_DIR/report.txt"
LOG_FILE="$CACHE_DIR/update-check.log"

kv_get() {
    local file="$1"
    local key="$2"
    local line

    [[ -r "$file" ]] || return 1
    line="$(grep -m1 -E "^${key}=" -- "$file" 2>/dev/null || true)"
    [[ -n "$line" ]] || return 1
    printf '%s\n' "${line#*=}"
}

status="$(kv_get "$STATUS_FILE" status || echo unknown)"
title="$(kv_get "$STATUS_FILE" title || echo "Update check")"
message="$(kv_get "$STATUS_FILE" message || echo "No details available.")"

clear 2>/dev/null || true

printf '\n'
printf '  %s\n' "$title"
printf '  ==========================================================\n\n'
printf '  Status : %s\n' "$status"
printf '  %s\n\n' "$message"
printf '  ----------------------------------------------------------\n\n'

if [[ -r "$REPORT_TXT" ]]; then
    cat "$REPORT_TXT"
else
    printf '  No report file found at %s\n' "$REPORT_TXT"
fi

printf '\n  Log: %s\n' "$LOG_FILE"
printf '\n  Press any key to close (auto-closes in 60s)...'

IFS= read -r -t 60 -n 1 _ 2>/dev/null || true

printf '\n'
