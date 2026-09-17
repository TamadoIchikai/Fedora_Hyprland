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

# Hyprland window addresses are hex, optionally with 0x prefix.
readonly ADDRESS_RE='^(0x)?[0-9a-fA-F]+$'

# Workspace the monitored apps are parked on when not in use.
readonly HIDDEN_WORKSPACE=11

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

lua_sq() {
  local out="$1"
  out="${out//\\/\\\\}"
  out="${out//\'/\\\'}"
  printf '%s' "$out"
}

is_valid_address() {
  [[ "$1" =~ $ADDRESS_RE ]]
}

is_valid_workspace() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

hypr_dispatch() {
  hyprctl dispatch "$1" >/dev/null 2>&1
}

# move_to_workspace <address> <workspace> <follow?>
move_to_workspace() {
  hypr_dispatch "hl.dsp.window.move({ workspace = $2, window = 'address:$1', follow = $3 })"
}

# focus_window <address>
focus_window() {
  hypr_dispatch "hl.dsp.focus({ window = 'address:$1' })"
}

# ---- preflight ----
[ -n "$APP_CLASS" ] || graceful_exit "no APP_CLASS"
[ -n "$LAUNCH_CMD" ] || graceful_exit "no LAUNCH_CMD"

need_cmd hyprctl
need_cmd jq

# ---- helpers ----
get_window_info() {
  hyprctl clients -j 2>/dev/null \
    | jq -r --arg c "$APP_CLASS" '
        limit(1; .[] | select(.class == $c))
        | "\(.address)\t\(.workspace.id)"
      ' 2>/dev/null
}

# ---- main ----
current_ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id' 2>/dev/null)
[ -n "$current_ws" ] || graceful_exit "could not read current workspace"
is_valid_workspace "$current_ws" || graceful_exit "invalid workspace id: $current_ws"

window_info="$(get_window_info)"
window_addr="${window_info%%$'\t'*}"
launch_cmd_lua="$(lua_sq "$LAUNCH_CMD")"

if [ -z "$window_addr" ]; then
  # Not running: start it on the hidden workspace, silently.
  hypr_dispatch "hl.dsp.exec_cmd('$launch_cmd_lua', { workspace = '${HIDDEN_WORKSPACE} silent' })" \
    || graceful_exit "failed to exec"

  # Wait for the window to appear (slow starters can take >1s).
  for _ in {1..8}; do
    sleep 0.25
    window_info="$(get_window_info)"
    window_addr="${window_info%%$'\t'*}"
    [ -n "$window_addr" ] && break
  done

  if [ -n "$window_addr" ]; then
    is_valid_address "$window_addr" || graceful_exit "invalid window address"
    move_to_workspace "$window_addr" "$current_ws" true
    focus_window "$window_addr"
  else
    log "launched but window not found yet (class=$APP_CLASS)"
  fi

  graceful_exit "done (launched)"
fi

app_ws="${window_info##*$'\t'}"
[ -n "$app_ws" ] || graceful_exit "could not read app workspace"
is_valid_workspace "$app_ws" || graceful_exit "invalid app workspace: $app_ws"
is_valid_address "$window_addr" || graceful_exit "invalid window address"

if [ "$app_ws" = "$current_ws" ]; then
  # App is visible on current workspace: hide it back to the hidden workspace.
  move_to_workspace "$window_addr" "$HIDDEN_WORKSPACE" false
else
  # App exists elsewhere: bring it to current workspace and focus it.
  move_to_workspace "$window_addr" "$current_ws" true
  focus_window "$window_addr"
fi

graceful_exit "done (toggled)"
