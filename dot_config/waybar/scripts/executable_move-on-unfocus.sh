#!/usr/bin/env bash
# Move specific apps to workspace 11 (only when safe to do so)
# Updated for Hyprland 0.55 Lua dispatcher syntax.

set -euo pipefail

readonly TARGET_WORKSPACE=11
readonly CHECK_INTERVAL=0.5
readonly GRACE_PERIOD_MS=500

# Hyprland window addresses are hex, optionally with 0x prefix.
readonly ADDRESS_RE='^(0x)?[0-9a-fA-F]+$'

readonly APPS=(
  "org.pulseaudio.pavucontrol"
  "blueman-manager"
  "org.localsend.localsend_app"
)

need_cmd() {
  command -v "$1" &>/dev/null || { echo "Required command not found: $1" >&2; exit 1; }
}

validate_address() {
  [[ "$1" =~ $ADDRESS_RE ]]
}

declare -A monitored_apps
for app in "${APPS[@]}"; do
  monitored_apps["$app"]=1
done

declare -A last_interaction_time

get_timestamp_ms() {
  date +%s%3N
}

is_app_monitored() {
  [[ -n "${monitored_apps["$1"]+x}" ]]
}

move_window_silent() {
  local address="$1"

  validate_address "$address" || return 0

  hyprctl dispatch \
    "hl.dsp.window.move({ workspace = ${TARGET_WORKSPACE}, window = 'address:${address}', follow = false })" \
    &>/dev/null || true
}

main() {
  need_cmd hyprctl
  need_cmd jq

  echo "Window mover started (workspace ${TARGET_WORKSPACE})"
  echo "Monitoring: ${APPS[*]}"
  echo "Grace period: 0.5s"

  while true; do
    now=$(get_timestamp_ms)

    # activewindow is the only reliable source for focus; clients for candidates.
    focused_class=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty')
    current_ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty')

    if [[ -n "$focused_class" ]] && is_app_monitored "$focused_class"; then
      last_interaction_time["$focused_class"]=$now
    fi

    if [[ "$current_ws" == "$TARGET_WORKSPACE" ]]; then
      sleep "$CHECK_INTERVAL"
      continue
    fi

    hyprctl clients -j 2>/dev/null | jq -r --argjson target "$TARGET_WORKSPACE" '
      .[] | select(.workspace.id != $target) | "\(.class)|\(.address)"
    ' | while IFS='|' read -r class address; do
      [[ -z "$class" ]] && continue
      [[ -z "$address" ]] && continue

      is_app_monitored "$class" || continue

      # Never move currently focused window.
      [[ "$class" == "$focused_class" ]] && continue

      last_seen=${last_interaction_time["$class"]:-0}
      time_since_interaction=$((now - last_seen))

      if (( time_since_interaction < GRACE_PERIOD_MS )); then
        continue
      fi

      echo "Moving $class to workspace $TARGET_WORKSPACE"
      move_window_silent "$address"

      sleep 0.05
    done

    sleep "$CHECK_INTERVAL"
  done
}

trap 'printf "\nShutting down...\n"; exit 0' SIGINT SIGTERM

main
