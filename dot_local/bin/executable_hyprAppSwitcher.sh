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

    # 1. Exclude the currently focused window completely
    # 2. Exclude other background apps on the current workspace
    | map(select(
        .address != $current_addr
        and .workspace.id != $current_ws_id
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
        .address
    ]
    | @tsv
' <<< "$clients_json" | while IFS=$'\t' read -r ws_id class title addr; do
    title="${title//$'\t'/ }"
    title="${title//$'\n'/ }"

    label="$(printf '%-4s %s  %s' "$ws_id" "$class" "$title")"

    # --- ICON OVERRIDE DICTIONARY ---
    # Default to using the window class as the icon name
    icon_hint="$class"
    
    # Override specific mismatched classes
    # Ensure you use lowercase for the match string
    case "${class,,}" in
        *zen*)
            # Fuzzel accepts absolute file paths. 
            # If this path doesn't match your system exactly, update it to point to your Zen icon.
            icon_hint="/opt/zen/browser/chrome/icons/default/default128.png"
            
            # Alternatively, if your system theme has a named icon for Zen, you can just use its name:
            # icon_hint="zen-browser"
            ;;
        *code-oss*)
            icon_hint="visual-studio-code" # Example of how to add more apps later
            ;;
    esac
    # ---------------------------------

    # Pass the corrected icon_hint to Fuzzel
    printf '%s\0icon\x1f%s\n' "$label" "$icon_hint" >> "$menu_file"
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
