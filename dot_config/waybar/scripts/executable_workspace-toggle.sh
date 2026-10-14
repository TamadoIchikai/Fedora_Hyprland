#!/usr/bin/env bash
source "$HOME/.config/abstractions/wm.sh"

# Hardened for Waybar click handlers:
# - quiet by default (no stdout/stderr noise)
# - exits 0 even on failures
# - validates deps/args
# - avoids common race/empty-json issues
# - updated for Hyprland 0.55 Lua dispatcher syntax

APP_CLASS="${1:-}"
LAUNCH_CMD="${2:-}"

DEBUG="${DEBUG:-0}"
LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/waybar-toggle-app.log"

# Workspace the monitored apps are parked on when not in use.
readonly HIDDEN_WORKSPACE="$(WM_park_workspace)"

log() {
  (( DEBUG )) || return 0
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  printf '[%s] %s\n' "$(date -Is)" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

graceful_exit() {
  log "exit: $*"
  exit 0
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing command: $1"
    graceful_exit "missing $1"
  }
}

is_valid_address() {
  WM_window_handle_valid "$1"
}

is_valid_workspace() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

# ---- preflight ----
[ -n "$APP_CLASS" ] || graceful_exit "no APP_CLASS"
[ -n "$LAUNCH_CMD" ] || graceful_exit "no LAUNCH_CMD"

need_cmd jq

# ---- helpers ----
get_window_info() {
  # Emits "<address>\t<workspace>\t<monitor>" for the first matching window.
  WM_window_list 2>/dev/null \
    | jq -r --arg c "$APP_CLASS" '
        limit(1; .[] | select(.class == $c))
        | "\(.address)\t\(.workspace.id)\t\(.monitor // "")"
      ' 2>/dev/null
}

# Split a "<address>\t<workspace>\t<monitor>" record into window_addr/app_ws/app_mon.
parse_window_info() {
  IFS=$'\t' read -r window_addr app_ws app_mon <<<"$1"
}

# ---- main ----
current_ws=$(WM_workspace_active 2>/dev/null)
[ -n "$current_ws" ] || graceful_exit "could not read current workspace"
is_valid_workspace "$current_ws" || graceful_exit "invalid workspace id: $current_ws"

# Mango tags are per-monitor: "current workspace" only means the focused
# monitor's tag. The focused monitor is re-read just before deciding.
focused_mon=$(WM_monitor_focused 2>/dev/null)

window_info="$(get_window_info)"
parse_window_info "$window_info"

if [ -z "$window_addr" ]; then
  # Not running: start it on the hidden workspace, silently.
  WM_exec_on_workspace "$HIDDEN_WORKSPACE" "$LAUNCH_CMD" \
    || graceful_exit "failed to exec"

  # Wait for the window to appear (slow starters can take >1s).
  for _ in {1..8}; do
    sleep 0.25
    window_info="$(get_window_info)"
    parse_window_info "$window_info"
    [ -n "$window_addr" ] && break
  done

  if [ -n "$window_addr" ]; then
    is_valid_address "$window_addr" || graceful_exit "invalid window address"
    WM_window_move_to_workspace "$window_addr" "$current_ws" true
    WM_window_focus "$window_addr"
  else
    log "launched but window not found yet (class=$APP_CLASS)"
  fi

  graceful_exit "done (launched)"
fi

[ -n "$app_ws" ] || graceful_exit "could not read app workspace"
is_valid_workspace "$app_ws" || graceful_exit "invalid app workspace: $app_ws"
is_valid_address "$window_addr" || graceful_exit "invalid window address"

focused_mon="$(WM_monitor_focused 2>/dev/null)"

if [ "$app_ws" = "$current_ws" ] && [ "$app_mon" = "$focused_mon" ]; then
  # App is visible here (same tag on the focused monitor): hide it to park.
  WM_window_move_to_workspace "$window_addr" "$HIDDEN_WORKSPACE" false
else
  # App is elsewhere (different tag and/or different monitor): show it here.
  WM_window_move_to_workspace "$window_addr" "$current_ws" true
  WM_window_focus "$window_addr"
fi

graceful_exit "done (toggled)"
