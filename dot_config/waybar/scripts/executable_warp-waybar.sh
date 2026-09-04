#!/usr/bin/env bash

# Waybar-safe Cloudflare WARP toggle/status
# - default mode prints ONLY JSON and exits 0
# - toggle mode is quiet (no stdout/stderr) and exits 0
# - logs to a file; optional DEBUG=1 for extra logs

set -u  # (no -e; we don't want to hard-fail in a click handler)

# Pin PATH so a compromised/writable PATH entry can't substitute the tools
# this script shells out to (curl, warp-cli, notify-send).
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ICON_ON='󰴴'
ICON_OFF='󰦜'
ICON_UNKNOWN='󰲛'
TIMEOUT=5

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
LOG_FILE="${RUNTIME_DIR}/warp-toggle.log"

DEBUG="${DEBUG:-0}"

log() {
  (( DEBUG )) || return 0
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

# Always exit 0 so Waybar doesn't mark the module failed
graceful_exit() { log "exit: $*"; exit 0; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# Returns:
#   "on"  -> warp=on
#   "off" -> warp is not on (including warp=off)
#   ""    -> unknown (curl failed / no network)
get_warp_state() {
  # If curl fails/timeouts, return unknown
  local warp
  # --proto '=https' hard-fails if the URL scheme ever changes/degrades;
  # cert verification is on by default.
  warp="$(curl -fsS --proto '=https' --max-time 1 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep '^warp=')" || { printf ''; return 0; }

  case "${warp#warp=}" in
    on) printf 'on' ;;
    *)  printf 'off' ;;
  esac
}

wait_for_state() {
  local target="$1" deadline=$(( SECONDS + TIMEOUT ))
  while [ "$SECONDS" -lt "$deadline" ]; do
    [ "$(get_warp_state)" = "$target" ] && return 0
    sleep 0.5
  done
  return 1
}

waybar_print() {
  # Print valid JSON only
  local state="$1"

  if [ "$state" = "on" ]; then
    printf '{"text":"%s","tooltip":"WARP: Connected","class":"connected"}\n' "$ICON_ON"
  elif [ "$state" = "off" ]; then
    printf '{"text":"%s","tooltip":"WARP: Disconnected","class":"disconnected"}\n' "$ICON_OFF"
  else
    printf '{"text":"%s","tooltip":"WARP: Unknown (network?)","class":"unknown"}\n' "$ICON_UNKNOWN"
  fi
}

set_target_state() {
  local target="$1" icon="$2"
  local active
  [ "$target" = "on" ] && active="Connect" || active="Disconnect"

  log "Attempting $active"
  notify-send "$icon  WARP" "$active..." -u low >/dev/null 2>&1 || true

  if [ "$target" = "on" ]; then
    warp-cli connect >/dev/null 2>&1 || true
  else
    warp-cli disconnect >/dev/null 2>&1 || true
  fi

  if wait_for_state "$target"; then
    notify-send "$icon  WARP" "$active" -u low >/dev/null 2>&1 || true
    log "$active successful"
  else
    notify-send "$icon  WARP" "Failed to $active" -u normal >/dev/null 2>&1 || true
    log "$active timeout/failure"
    warp-cli disconnect >/dev/null 2>&1 || true
  fi
}

toggle() {
  # No stdout/stderr output in toggle mode
  have_cmd warp-cli || graceful_exit "warp-cli missing"

  local state
  state="$(get_warp_state)"

  if [ "$state" = "on" ]; then
    set_target_state "off" "$ICON_OFF"
  else
    set_target_state "on" "$ICON_ON"
  fi

  graceful_exit "toggle done"
}

# ---- entrypoint ----
if [ "${1:-}" = "toggle" ]; then
  toggle
fi

# Default: status output for Waybar
state="$(get_warp_state)"
waybar_print "$state"
graceful_exit "printed status"
