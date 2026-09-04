#!/usr/bin/env bash
set -euo pipefail

LAYOUTS=(keyboard-us unikey mozc)
STATE="$HOME/.cache/fcitx5_keyboard_state"
DOUBLE_TAP_MS="${DOUBLE_TAP_MS:-300}"

cur=$(fcitx5-remote -n)
now=$(date +%s%3N)

last_ms=0
prev=""
if [[ -f "$STATE" ]]; then
    read -r last_ms prev < "$STATE" || true
else
    mkdir -p "$(dirname "$STATE")"
    : > "$STATE"
fi
# The state file records user activity (last-used layout + timing); keep it
# owner-only so other local users cannot read it, even when ~/.cache is 755.
chmod 600 "$STATE"

target=""
if (( last_ms > 0 && now - last_ms <= DOUBLE_TAP_MS )); then
    for l in "${LAYOUTS[@]}"; do
        [[ "$l" != "$cur" && "$l" != "$prev" ]] && { target="$l"; break; }
    done
else
    target="$prev"
    if [[ -z "$target" || "$target" == "$cur" ]]; then
        idx=0
        for i in "${!LAYOUTS[@]}"; do
            [[ "${LAYOUTS[$i]}" == "$cur" ]] && { idx=$i; break; }
        done
        target="${LAYOUTS[((idx + 1) % ${#LAYOUTS[@]})]}"
    fi
fi

[[ -n "$target" ]] && fcitx5-remote -s "$target"
printf '%s %s\n' "$now" "$cur" > "$STATE"
