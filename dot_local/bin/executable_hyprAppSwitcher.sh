#!/usr/bin/env bash
set -euo pipefail

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

menu_file="$tmpdir/menu"
addr_file="$tmpdir/addr"

command -v hyprctl >/dev/null || exit 1
command -v jq >/dev/null || exit 1
command -v fuzzel >/dev/null || exit 1

active_window_json="$(hyprctl activewindow -j 2>/dev/null || echo '{}')"

current_addr="$(
  jq -r '.address // ""' <<< "$active_window_json"
)"

current_ws_id="$(
  jq -r '.workspace.id // empty' <<< "$active_window_json"
)"

# Fallback if activewindow does not provide workspace info
if [[ -z "$current_ws_id" ]]; then
  current_ws_id="$(hyprctl activeworkspace -j | jq -r '.id')"
fi

hyprctl clients -j | jq -r \
  --arg current_addr "$current_addr" \
  --argjson current_ws_id "$current_ws_id" '
  map(select(
    .mapped == true
    and .hidden == false
    and .class != ""
    and .focusHistoryID != null
  ))

  # Most recently focused first
  | sort_by(.focusHistoryID)

  # Exclude windows on current workspace,
  # except the currently focused window
  | map(select(
    (.workspace.id != $current_ws_id)
    or (.address == $current_addr)
  ))

  # One item per app class.
  # Because we already sorted by focusHistoryID,
  # this keeps the most recently used window for each app.
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
' | while IFS=$'\t' read -r ws_id class title addr marker; do
    if [[ "$marker" == "CURRENT" ]]; then
        name="● CURRENT  $class  $title"
    else
        name="$class  $title"
    fi

    # Visible layout:
    # [icon] [workspace_number] [app/title]
    #
    # The workspace column only contains the workspace number.
    printf '%-4s %s\0icon\x1f%s,application-x-executable\n' \
        "$ws_id" "$name" "$class" >> "$menu_file"

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
