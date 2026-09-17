#!/usr/bin/env bash
# Move specific apps to workspace 11 (only when safe to do so)
# Updated for Hyprland 0.55 Lua dispatcher syntax.
#
# Robustness:
#  - arrival tracking: a window that just landed on a non-target workspace
#    (launched via workspace-toggle.sh, or reshuffled by a monitor layout
#    change) is never yanked back to workspace 11 immediately.
#  - the focus snapshot is re-read immediately before dispatching each move,
#    closing the race where focus lands between detection and dispatch.
#  - entries for closed windows are garbage-collected.

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

declare -A last_interaction_time   # class   -> ms it was last observed focused
declare -A window_workspace        # address -> workspace id last observed on
declare -A window_arrival_time     # address -> ms it entered that workspace

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

activewindow_info() {
  hyprctl activewindow -j 2>/dev/null | jq -r '"\(.class // "")|\(.address // "")"'
}

main() {
  need_cmd hyprctl
  need_cmd jq

  echo "Window mover started (workspace ${TARGET_WORKSPACE})"
  echo "Monitoring: ${APPS[*]}"
  echo "Grace period: ${GRACE_PERIOD_MS}ms"

  while true; do
    now=$(get_timestamp_ms)

    current_ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty')

    # Nothing to do while parked on the target workspace: skip the snapshot.
    if [[ "$current_ws" == "$TARGET_WORKSPACE" ]]; then
      sleep "$CHECK_INTERVAL"
      continue
    fi

    # Snapshot every monitored window + its workspace. Process substitution
    # (not a pipe) keeps the while loop in THIS shell, so the tracking arrays
    # below actually persist.
    declare -A seen=()
    declare -a candidates=()
    while IFS='|' read -r class address ws; do
      [[ -n "$class" ]] || continue
      [[ -n "$address" ]] || continue
      is_app_monitored "$class" || continue
      validate_address "$address" || continue

      seen["$address"]=1
      if [[ "${window_workspace[$address]-}" != "$ws" ]]; then
        window_workspace["$address"]="$ws"
        window_arrival_time["$address"]=$now
      fi

      [[ "$ws" == "$TARGET_WORKSPACE" ]] && continue
      candidates+=("$class|$address")
    done < <(hyprctl clients -j 2>/dev/null | jq -r '
      .[] | "\(.class // "")|\(.address // "")|\(.workspace.id)"
    ')

    # Only read focus when something might move: this both stamps a focused
    # monitored app (so its grace window starts) and closes the race where
    # focus lands between the snapshot above and the dispatch below. Idle
    # ticks — every monitored window parked — skip this IPC call entirely.
    focused_address=""
    if (( ${#candidates[@]} > 0 )); then
      focused_info="$(activewindow_info)"
      focused_class="${focused_info%%|*}"
      focused_address="${focused_info#*|}"
      if [[ -n "$focused_class" ]] && is_app_monitored "$focused_class"; then
        last_interaction_time["$focused_class"]=$now
      fi
    fi

    for entry in "${candidates[@]}"; do
      class="${entry%%|*}"
      address="${entry#*|}"

      # Never move the currently focused window.
      [[ -n "$focused_address" && "$address" == "$focused_address" ]] && continue
      # Never move a window that just arrived on this workspace.
      (( now - ${window_arrival_time[$address]:-0} < GRACE_PERIOD_MS )) && continue
      # Never move a window its user just interacted with.
      (( now - ${last_interaction_time[$class]:-0} < GRACE_PERIOD_MS )) && continue

      echo "Moving $class to workspace $TARGET_WORKSPACE"
      move_window_silent "$address"

      sleep 0.05
    done

    # Garbage-collect entries for windows that no longer exist.
    for addr in "${!window_workspace[@]}"; do
      [[ -n "${seen[$addr]+x}" ]] || {
        unset window_workspace[$addr]
        unset window_arrival_time[$addr]
      }
    done

    sleep "$CHECK_INTERVAL"
  done
}

trap 'printf "\nShutting down...\n"; exit 0' SIGINT SIGTERM

main