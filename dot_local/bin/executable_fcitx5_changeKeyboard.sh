#!/usr/bin/env bash
set -euo pipefail

LAYOUTS=(keyboard-us unikey mozc)
declare -A LAYOUT_LABEL=([keyboard-us]="keyboard" [unikey]="keyboard" [mozc]="keyboard")
ICON_BASE="/usr/share/icons/Papirus-Dark/24x24/panel"
declare -A LAYOUT_ICON=([keyboard-us]="$ICON_BASE/indicator-keyboard-En.svg" [unikey]="$ICON_BASE/indicator-keyboard-Vi.svg" [mozc]="$ICON_BASE/indicator-keyboard-Ja.svg")
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

if [[ -n "$target" ]]; then
    fcitx5-remote -s "$target"
    label="${LAYOUT_LABEL[$target]:-$target}"
    icon="${LAYOUT_ICON[$target]:-/usr/share/icons/Adwaita/scalable/devices/input-keyboard.svg}"
    command -v notify-send >/dev/null 2>&1 && notify-send -e -i "$icon" -a fcitx5 -t 700 "$label" &
fi
printf '%s %s\n' "$now" "$cur" > "$STATE"
