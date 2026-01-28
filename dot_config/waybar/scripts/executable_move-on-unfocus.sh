#!/usr/bin/env bash
# Move specific apps to workspace 10 (only when safe to do so)

set -euo pipefail

readonly TARGET_WORKSPACE=10
readonly CHECK_INTERVAL=0.5
readonly GRACE_PERIOD_SEC=0.5

readonly APPS=(
  "org.pulseaudio.pavucontrol"
  "blueman-manager"
  "localsend"
)

declare -A last_interaction_time

# Get timestamp in milliseconds for better precision
get_timestamp_ms() {
  date +%s%3N
}

# Convert seconds to milliseconds
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

main() {
  local grace_period_ms=$(sec_to_ms "$GRACE_PERIOD_SEC")
  
  echo "Window mover started (workspace ${TARGET_WORKSPACE})"
  echo "Monitoring: ${APPS[*]}"
  echo "Grace period: ${GRACE_PERIOD_SEC}s"

  while true; do
    now=$(get_timestamp_ms)
    
    # Get current workspace and focused window
    active_data=$(hyprctl activewindow -j 2>/dev/null)
    focused_class=$(echo "$active_data" | jq -r '.class // empty')
    current_ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty')
    
    # Update interaction time for focused window
    if [[ -n "$focused_class" ]] && is_app_monitored "$focused_class"; then
      last_interaction_time["$focused_class"]=$now
    fi
    
    # Only process if we're NOT on the target workspace
    if [[ "$current_ws" == "$TARGET_WORKSPACE" ]]; then
      sleep "$CHECK_INTERVAL"
      continue
    fi
    
    # Find windows to move
    hyprctl clients -j 2>/dev/null | jq -r '.[] | 
      select(.workspace.id != '"$TARGET_WORKSPACE"') | 
      "\(.class)|\(.address)|\(.workspace.id)"
    ' | while IFS='|' read -r class address workspace; do
      [[ -z "$class" ]] && continue
      
      # Check if this is a monitored app
      is_app_monitored "$class" || continue
      
      # Never move currently focused window
      [[ "$class" == "$focused_class" ]] && continue
      
      # Check grace period (now in milliseconds)
      last_seen=${last_interaction_time["$class"]:-0}
      time_since_interaction=$((now - last_seen))
      
      if (( time_since_interaction < grace_period_ms )); then
        continue
      fi
      
      # Move the window
      echo "Moving $class to workspace $TARGET_WORKSPACE"
      hyprctl dispatch movetoworkspacesilent "${TARGET_WORKSPACE},address:${address}" &>/dev/null
      
      # Small delay to avoid race conditions
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
