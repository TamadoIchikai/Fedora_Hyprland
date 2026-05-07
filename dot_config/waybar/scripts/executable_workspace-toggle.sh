#!/usr/bin/env bash

# Hardened for Waybar click handlers:
# - quiet by default (no stdout/stderr noise)
# - exits 0 even on failures (so Waybar won't treat it as a hard error)
# - validates deps/args
# - avoids common race/empty-json issues

APP_CLASS="${1:-}"
LAUNCH_CMD="${2:-}"

# Optional: set DEBUG=1 in Waybar env to log to a file.
DEBUG="${DEBUG:-0}"
LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/waybar-toggle-app.log"

log() {
  (( DEBUG )) || return 0
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  printf '[%s] %s\n' "$(date -Is)" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

# Keep Waybar clean: never emit output unless DEBUG logging is enabled.
quiet_exec() {
  "$@" >/dev/null 2>&1
}

# Always exit successfully to avoid Waybar module failure behavior.
graceful_exit() {
  log "exit: $*"
  exit 0
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log "missing command: $1"; graceful_exit "missing $1"; }
}

# ---- preflight ----
[ -n "$APP_CLASS" ] || graceful_exit "no APP_CLASS"
[ -n "$LAUNCH_CMD" ] || graceful_exit "no LAUNCH_CMD"

need_cmd hyprctl
need_cmd jq

# If Hyprland/IPC isn't available, hyprctl will fail; just bail quietly.
hyprctl clients -j >/dev/null 2>&1 || graceful_exit "hyprctl IPC not available"

# ---- helpers to query hyprctl safely ----
get_first_window_addr_by_class() {
  hyprctl clients -j 2>/dev/null \
    | jq -r --arg c "$APP_CLASS" '.[] | select(.class == $c) | .address' 2>/dev/null \
    | head -n1
}

get_first_window_ws_by_class() {
  hyprctl clients -j 2>/dev/null \
    | jq -r --arg c "$APP_CLASS" '.[] | select(.class == $c) | .workspace.id' 2>/dev/null \
    | head -n1
}

get_current_ws() {
  hyprctl activeworkspace -j 2>/dev/null | jq -r '.id' 2>/dev/null
}

# ---- main ----
current_ws="$(get_current_ws)"
[ -n "$current_ws" ] || graceful_exit "could not read current workspace"

window_addr="$(get_first_window_addr_by_class)"

if [ -z "$window_addr" ]; then
  # Not running: start it on workspace 11, then bring to current workspace
  # NOTE: LAUNCH_CMD is intentionally passed as a single string to hyprctl exec.
  quiet_exec hyprctl dispatch exec "[workspace 11 silent] $LAUNCH_CMD" || graceful_exit "failed to exec"

  # Wait a bit for the window to appear (retry instead of a single sleep)
  for _ in 1 2 3 4 5; do
    sleep 0.15
    window_addr="$(get_first_window_addr_by_class)"
    [ -n "$window_addr" ] && break
  done

  if [ -n "$window_addr" ]; then
    quiet_exec hyprctl dispatch movetoworkspace "$current_ws,address:$window_addr"
    quiet_exec hyprctl dispatch focuswindow "address:$window_addr"
  else
    log "launched but window not found yet (class=$APP_CLASS)"
  fi

  graceful_exit "done (launched)"
fi

app_ws="$(get_first_window_ws_by_class)"
[ -n "$app_ws" ] || graceful_exit "could not read app workspace"

if [ "$app_ws" = "$current_ws" ]; then
  quiet_exec hyprctl dispatch movetoworkspacesilent "11,address:$window_addr"
else
  quiet_exec hyprctl dispatch movetoworkspace "$current_ws,address:$window_addr"
  quiet_exec hyprctl dispatch focuswindow "address:$window_addr"
fi

graceful_exit "done (toggled)"
