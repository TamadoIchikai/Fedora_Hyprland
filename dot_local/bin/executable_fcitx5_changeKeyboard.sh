#!/usr/bin/env bash
# Switch fcitx5 input methods in most-recently-used order.
#   Single tap: switch to the previously used IM.
#   Double tap (<= DOUBLE_TAP_MS): switch to the least-recently-used IM.
# The MRU order lives in $STATE only; the fcitx5 profile is never modified.
set -uo pipefail
umask 077

LAYOUTS=(keyboard-us unikey mozc)
declare -A LAYOUT_LABEL=([keyboard-us]="keyboard" [unikey]="keyboard" [mozc]="keyboard")
ICON_BASE="/usr/share/icons/Papirus-Dark/24x24/panel"
declare -A LAYOUT_ICON=([keyboard-us]="$ICON_BASE/indicator-keyboard-En.svg" [unikey]="$ICON_BASE/indicator-keyboard-Vi.svg" [mozc]="$ICON_BASE/indicator-keyboard-Ja.svg")
STATE="$HOME/.cache/fcitx5_keyboard_state"
PROFILE="$HOME/.config/fcitx5/profile"
DOUBLE_TAP_MS="${DOUBLE_TAP_MS:-300}"
[[ "$DOUBLE_TAP_MS" =~ ^[0-9]+$ ]] || DOUBLE_TAP_MS=300

notify() { # notify <icon> <summary> [body]
    command -v notify-send >/dev/null 2>&1 || return 0
    local icon="$1"
    [[ -r "$icon" ]] || icon="input-keyboard"
    notify-send -e -a fcitx5 -t 700 -i "$icon" \
        -h string:x-canonical-private-synchronous:fcitx5-ime \
        "$2" ${3:+"$3"} >/dev/null 2>&1 &
}

die() {
    notify "dialog-error" "fcitx5" "$1"
    printf '%s: %s\n' "${0##*/}" "$1" >&2
    exit 1
}

get_im_order() {
    [[ -r "$PROFILE" ]] || return 1
    awk '
        /^\[Groups\/0\/Items\// { in_item = 1; next }
        /^\[/ { in_item = 0 }
        in_item && /^Name=/ { sub(/^Name=/, ""); print }
    ' "$PROFILE"
}

has() { # has <needle> <haystack...>
    local n="$1" x
    shift
    for x in "$@"; do [[ "$x" == "$n" ]] && return 0; done
    return 1
}

# sanitize <space-separated list>: print a valid MRU (one per line) containing
# exactly the entries of avail, keeping the given order where valid.
sanitize() {
    local -a in=() out=()
    local x
    read -r -a in <<< "${1:-}"
    for x in "${in[@]}"; do
        has "$x" "${avail[@]}" && ! has "$x" "${out[@]}" && out+=("$x")
    done
    for x in "${avail[@]}"; do
        has "$x" "${out[@]}" || out+=("$x")
    done
    printf '%s\n' "${out[@]}"
}

# to_front <item> <list...>: print item followed by list without item.
to_front() {
    local t="$1" x
    shift
    printf '%s\n' "$t"
    for x in "$@"; do [[ "$x" == "$t" ]] || printf '%s\n' "$x"; done
}

# --- setup & lock -----------------------------------------------------------
mkdir -p "${STATE%/*}" || die "cannot create ${STATE%/*}"
exec 9>"$STATE.lock" || die "cannot open lock file"
flock -w 1 9 || exit 0

# --- dependencies -----------------------------------------------------------
command -v fcitx5-remote >/dev/null 2>&1 || die "fcitx5-remote not found"
cur=$(fcitx5-remote -n 2>/dev/null) && [[ -n "$cur" ]] || die "fcitx5 is not running"

# --- available IMs ----------------------------------------------------------
avail=()
mapfile -t avail < <(get_im_order 2>/dev/null)
(( ${#avail[@]} > 0 )) || avail=("${LAYOUTS[@]}")

now=$(( ${EPOCHREALTIME//[!0-9]/} / 1000 ))

# --- state ------------------------------------------------------------------
st=()
[[ -r "$STATE" ]] && mapfile -t -n 3 st < "$STATE"
last_ms="${st[0]:-0}"
[[ "$last_ms" =~ ^[0-9]+$ ]] || last_ms=0
mapfile -t mru < <(sanitize "${st[1]:-}")
prev=()
[[ -n "${st[2]:-}" ]] && mapfile -t prev < <(sanitize "${st[2]}")

# Reflect switches made elsewhere (trigger key, tray, ...).
has "$cur" "${avail[@]}" && mapfile -t mru < <(to_front "$cur" "${mru[@]}")

# --- pick target ------------------------------------------------------------
if (( last_ms > 0 && now >= last_ms && now - last_ms <= DOUBLE_TAP_MS && ${#prev[@]} > 0 )); then
    base=("${prev[@]}")
    target="${base[-1]}"
    mapfile -t mru < <(to_front "$target" "${base[@]}")
    prev=("${base[@]}")
else
    prev=("${mru[@]}")
    if (( ${#mru[@]} > 1 )); then target="${mru[1]}"; else target="${mru[0]}"; fi
    mapfile -t mru < <(to_front "$target" "${mru[@]}")
fi

# --- switch -----------------------------------------------------------------
if [[ "$target" != "$cur" ]]; then
    fcitx5-remote -s "$target" >/dev/null 2>&1 || die "failed to switch to $target"
    switched=1
else
    switched=0
fi

# --- save state (atomic) ----------------------------------------------------
tmp=$(mktemp "$STATE.XXXXXX") || die "cannot write state"
if printf '%s\n%s\n%s\n' "$now" "${mru[*]}" "${prev[*]}" > "$tmp" && mv -f "$tmp" "$STATE"; then
    :
else
    rm -f "$tmp"
fi

# --- notify -----------------------------------------------------------------
(( switched )) && notify "${LAYOUT_ICON[$target]:-}" "${LAYOUT_LABEL[$target]:-$target}"
exit 0
