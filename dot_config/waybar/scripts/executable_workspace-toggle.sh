#!/usr/bin/env bash

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

log() {
  (( DEBUG )) || return 0
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  printf '[%s] %s\n' "$(date -Is)" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

quiet_exec() {
  "$@" >/dev/null 2>&1
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

# Escape a string so it can be safely placed inside a Lua single-quoted string.
lua_sq() {
  printf "%s" "$1" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g"
}

hypr_dispatch() {
  quiet_exec hyprctl dispatch "$1"
}

# ---- preflight ----
[ -n "$APP_CLASS" ] || graceful_exit "no APP_CLASS"
[ -n "$LAUNCH_CMD" ] || graceful_exit "no LAUNCH_CMD"

need_cmd hyprctl
need_cmd jq
need_cmd sed

hyprctl clients -j >/dev/null 2>&1 || graceful_exit "hyprctl IPC not available"

# ---- helpers ----
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
launch_cmd_lua="$(lua_sq "$LAUNCH_CMD")"

if [ -z "$window_addr" ]; then
  # Not running: start it on workspace 11 silently.
  hypr_dispatch "hl.dsp.exec_cmd('$launch_cmd_lua', { workspace = '11 silent' })" \
    || graceful_exit "failed to exec"

  # Wait for the window to appear.
  for _ in 1 2 3 4 5; do
    sleep 0.15
    window_addr="$(get_first_window_addr_by_class)"
    [ -n "$window_addr" ] && break
  done

  if [ -n "$window_addr" ]; then
    hypr_dispatch "hl.dsp.window.move({ workspace = $current_ws, window = 'address:$window_addr', follow = true })"
    hypr_dispatch "hl.dsp.focus({ window = 'address:$window_addr' })"
  else
    log "launched but window not found yet (class=$APP_CLASS)"
  fi

  graceful_exit "done (launched)"
fi

app_ws="$(get_first_window_ws_by_class)"
[ -n "$app_ws" ] || graceful_exit "could not read app workspace"

if [ "$app_ws" = "$current_ws" ]; then
  # App is visible on current workspace: hide it back to workspace 11.
  hypr_dispatch "hl.dsp.window.move({ workspace = 11, window = 'address:$window_addr', follow = false })"
else
  # App exists elsewhere: bring it to current workspace and focus it.
  hypr_dispatch "hl.dsp.window.move({ workspace = $current_ws, window = 'address:$window_addr', follow = true })"
  hypr_dispatch "hl.dsp.focus({ window = 'address:$window_addr' })"
fi

graceful_exit "done (toggled)"
