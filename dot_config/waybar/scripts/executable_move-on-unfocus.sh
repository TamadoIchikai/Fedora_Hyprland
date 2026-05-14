#!/usr/bin/env bash
# Move specific apps to workspace 11 (only when safe to do so)
# Updated for Hyprland 0.55 Lua dispatcher syntax.

set -euo pipefail

readonly TARGET_WORKSPACE=11
readonly CHECK_INTERVAL=0.5
readonly GRACE_PERIOD_SEC=0.5

readonly APPS=(
  "org.pulseaudio.pavucontrol"
  "blueman-manager"
  "localsend"
  "localsend_app"
)

declare -A last_interaction_time

get_timestamp_ms() {
  date +%s%3N
}

sec_to_ms() {
  awk "BEGIN {print int($1 * 1000)}"
}

is_app_monitored() {
  local class="$1"
  for app in "${APPS[@]}"; do
    [[ "$class" == "$app" ]] && return 0
  done
  return 1
}

move_window_silent() {
  local address="$1"

  hyprctl dispatch \
    "hl.dsp.window.move({ workspace = ${TARGET_WORKSPACE}, window = 'address:${address}', follow = false })" \
    &>/dev/null || true
}

main() {
  local grace_period_ms
  grace_period_ms=$(sec_to_ms "$GRACE_PERIOD_SEC")

  echo "Window mover started (workspace ${TARGET_WORKSPACE})"
  echo "Monitoring: ${APPS[*]}"
  echo "Grace period: ${GRACE_PERIOD_SEC}s"

  while true; do
    now=$(get_timestamp_ms)

    active_data=$(hyprctl activewindow -j 2>/dev/null || true)
    focused_class=$(echo "$active_data" | jq -r '.class // empty')
    current_ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty')

    if [[ -n "$focused_class" ]] && is_app_monitored "$focused_class"; then
      last_interaction_time["$focused_class"]=$now
    fi

    if [[ "$current_ws" == "$TARGET_WORKSPACE" ]]; then
      sleep "$CHECK_INTERVAL"
      continue
    fi

    hyprctl clients -j 2>/dev/null | jq -r '.[] |
      select(.workspace.id != '"$TARGET_WORKSPACE"') |
      "\(.class)|\(.address)|\(.workspace.id)"
    ' | while IFS='|' read -r class address workspace; do
      [[ -z "$class" ]] && continue
      [[ -z "$address" ]] && continue

      is_app_monitored "$class" || continue

      # Never move currently focused window.
      [[ "$class" == "$focused_class" ]] && continue

      last_seen=${last_interaction_time["$class"]:-0}
      time_since_interaction=$((now - last_seen))

      if (( time_since_interaction < grace_period_ms )); then
        continue
      fi

      echo "Moving $class to workspace $TARGET_WORKSPACE"
      move_window_silent "$address"

      sleep 0.05
    done

    sleep "$CHECK_INTERVAL"
  done
}

cleanup() {
  echo -e "\nShutting down..."
  exit 0
}

trap cleanup SIGINT SIGTERM

main
