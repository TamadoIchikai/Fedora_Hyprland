#!/usr/bin/env bash
set -euo pipefail

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

menu_file="$tmpdir/menu"
addr_file="$tmpdir/addr"

command -v hyprctl >/dev/null || exit 1
command -v jq >/dev/null || exit 1
command -v fuzzel >/dev/null || exit 1

active_json="$(hyprctl activewindow -j 2>/dev/null || printf '{}\n')"
clients_json="$(hyprctl clients -j)"

current_addr="$(jq -r '.address // ""' <<< "$active_json")"
current_ws_id="$(jq -r '.workspace.id // empty' <<< "$active_json")"

if [[ -z "$current_ws_id" ]]; then
    current_ws_id="$(hyprctl activeworkspace -j | jq -r '.id // empty')"
fi

jq -r \
    --arg current_addr "$current_addr" \
    --argjson current_ws_id "${current_ws_id:-0}" '
    map(select(
        .mapped == true
        and .hidden == false
        and .class != ""
        and .focusHistoryID != null
    ))

    # Most recently focused first
    | sort_by(.focusHistoryID)

    # Exclude workspace 11
    | map(select(.workspace.id != 11))

    # Exclude apps from current workspace,
    # except the currently focused window
    | map(select(
        (.workspace.id != $current_ws_id)
        or (.address == $current_addr)
    ))

    # One item per app class
    | reduce .[] as $c (
        [];
        if any(.[]; .class == $c.class)
        then .
        else . + [$c]
        end
    )

    | .[]
    | [
        .workspace.id,
        .class,
        .title,
        .address,
        if .address == $current_addr then "CURRENT" else "" end
    ]
    | @tsv
' <<< "$clients_json" | while IFS=$'\t' read -r ws_id class title addr marker; do
    title="${title//$'\t'/ }"
    title="${title//$'\n'/ }"

    if [[ "$marker" == "CURRENT" ]]; then
        label="$(printf '%-4s %s  %s' "$ws_id" "$class" "$title")"
    else
        label="$(printf '%-4s %s  %s' "$ws_id" "$class" "$title")"
    fi

    # Simple Fuzzel dmenu icon hint.
    # No .desktop parsing, no icon cache, no fallback list.
    printf '%s\0icon\x1f%s\n' "$label" "$class" >> "$menu_file"
    printf '%s\n' "$addr" >> "$addr_file"
done

[[ -s "$menu_file" ]] || exit 0

index="$(
    fuzzel \
        --dmenu \
        --index \
        --prompt="Apps > " \
        --no-run-if-empty \
        < "$menu_file"
)" || exit 0

[[ -n "$index" ]] || exit 0

addr="$(sed -n "$((index + 1))p" "$addr_file")"

[[ -n "$addr" ]] || exit 0

hyprctl dispatch "hl.dsp.focus({ window = 'address:${addr}' })" >/dev/null
