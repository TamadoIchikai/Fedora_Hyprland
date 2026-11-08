#!/usr/bin/env bash
set -euo pipefail

LAYOUTS=(keyboard-us unikey mozc)
declare -A LAYOUT_LABEL=([keyboard-us]="keyboard" [unikey]="keyboard" [mozc]="keyboard")
ICON_BASE="/usr/share/icons/Papirus-Dark/24x24/panel"
declare -A LAYOUT_ICON=([keyboard-us]="$ICON_BASE/indicator-keyboard-En.svg" [unikey]="$ICON_BASE/indicator-keyboard-Vi.svg" [mozc]="$ICON_BASE/indicator-keyboard-Ja.svg")
STATE="$HOME/.cache/fcitx5_keyboard_state"
PROFILE="$HOME/.config/fcitx5/profile"
DOUBLE_TAP_MS="${DOUBLE_TAP_MS:-300}"

get_im_order() {
    [[ -f "$PROFILE" ]] || return 1
    awk '
        /^\[Groups\/0\/Items\// { in_item = 1; next }
        /^\[/ { in_item = 0 }
        in_item && /^Name=/ { sub(/^Name=/, ""); print }
    ' "$PROFILE"
}

reorder_profile() {
    local target="$1"
    shift
    local tmp start end
    local -a base_order=("$@") new_order=()
    local x i found=0

    [[ -f "$PROFILE" ]] || return 0

    if (( ${#base_order[@]} == 0 )); then
        mapfile -t base_order < <(get_im_order)
    fi
    (( ${#base_order[@]} > 1 )) || return 0

    for x in "${base_order[@]}"; do
        [[ "$x" == "$target" ]] && found=1
    done
    (( found == 1 )) || return 0
    [[ "${base_order[0]}" != "$target" ]] || return 0

    new_order=("$target")
    for x in "${base_order[@]}"; do
        [[ "$x" == "$target" ]] || new_order+=("$x")
    done
    (( ${#new_order[@]} == ${#base_order[@]} )) || return 0

    start="$(grep -n '^\[Groups/0/Items/0\]' "$PROFILE" | head -n 1 | cut -d: -f1)"
    end="$(grep -n '^\[GroupOrder\]' "$PROFILE" | head -n 1 | cut -d: -f1)"
    [[ -n "$start" && -n "$end" && "$start" -lt "$end" ]] || return 0

    tmp="$(mktemp "${PROFILE}.XXXXXX")" || return 0
    chmod --reference="$PROFILE" "$tmp" 2>/dev/null || chmod 600 "$tmp"

    head -n "$((start - 1))" "$PROFILE" > "$tmp"
    for i in "${!new_order[@]}"; do
        {
            printf '[Groups/0/Items/%d]\n' "$i"
            printf '# Name\n'
            printf 'Name=%s\n' "${new_order[$i]}"
            printf '# Layout\n'
            printf '# Layout=\n'
            printf '\n'
        } >> "$tmp"
    done
    tail -n +"$end" "$PROFILE" >> "$tmp"

    if ! mv -f "$tmp" "$PROFILE"; then
        rm -f "$tmp"
        return 0
    fi
}

cur=$(fcitx5-remote -n)
now=$(date +%s%3N)
cur_order=()
mapfile -t cur_order < <(get_im_order)
(( ${#cur_order[@]} > 0 )) || cur_order=("${LAYOUTS[@]}")

last_ms=0
prev=""
last_order=()
if [[ -f "$STATE" ]]; then
    marker=""
    order_str=""
    read -r last_ms marker order_str < "$STATE" || true
    if [[ "$marker" == "order" && -n "$order_str" ]]; then
        read -r -a last_order <<< "$order_str"
    fi
else
    mkdir -p "$(dirname "$STATE")"
    : > "$STATE"
fi
# The state file records user activity (last-used layout + timing); keep it
# owner-only so other local users cannot read it, even when ~/.cache is 755.
chmod 600 "$STATE"

target=""
if (( last_ms > 0 && now - last_ms <= DOUBLE_TAP_MS )); then
    base_order=()
    if (( ${#last_order[@]} > 0 )); then
        base_order=("${last_order[@]}")
    else
        mapfile -t base_order < <(get_im_order)
        (( ${#base_order[@]} > 0 )) || base_order=("${LAYOUTS[@]}")
    fi

    target="${base_order[${#base_order[@]}-1]}"
    if [[ -n "$target" && "$target" != "$cur" ]]; then
        reorder_profile "$target" "${base_order[@]}"
        fcitx5-remote -r >/dev/null 2>&1 || true
    else
        target=""
    fi
else
    # Single tap: move the next layout in the current order to the front.
    cur_order=()
    mapfile -t cur_order < <(get_im_order)
    if (( ${#cur_order[@]} == 0 )); then
        cur_order=("${LAYOUTS[@]}")
    fi
    idx=-1
    for i in "${!cur_order[@]}"; do
        [[ "${cur_order[$i]}" == "$cur" ]] && { idx=$i; break; }
    done
    if (( idx >= 0 )); then
        target="${cur_order[(( (idx + 1) % ${#cur_order[@]} ))]}"
    else
        target="${cur_order[0]}"
    fi
    reorder_profile "$target" "${cur_order[@]}"
    fcitx5-remote -r >/dev/null 2>&1 || true
fi

if [[ -n "$target" ]]; then
    fcitx5-remote -s "$target"
    label="${LAYOUT_LABEL[$target]:-$target}"
    icon="${LAYOUT_ICON[$target]:-/usr/share/icons/Adwaita/scalable/devices/input-keyboard.svg}"
    command -v notify-send >/dev/null 2>&1 && notify-send -e -i "$icon" -a fcitx5 -t 700 "$label" &
fi
printf '%s order %s\n' "$now" "${cur_order[*]}" > "$STATE"
