#!/usr/bin/env bash

# Waybar-safe Cloudflare WARP toggle/status
# - default mode prints ONLY JSON and exits 0
# - toggle mode is quiet (no stdout/stderr) and exits 0
# - logs to a file; optional DEBUG=1 for extra logs

set -u  # (no -e; we don't want to hard-fail in a click handler)

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
  local trace
  trace="$(curl -fsS --max-time 2 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)" || { printf ''; return 0; }

  if printf '%s\n' "$trace" | grep -q '^warp=on'; then
    printf 'on'
  elif printf '%s\n' "$trace" | grep -q '^warp='; then
    printf 'off'
  else
    # Unexpected format -> unknown
    printf ''
  fi
}

wait_for_state() {
  local target="$1" elapsed=0 state=""
  while [ "$elapsed" -lt "$TIMEOUT" ]; do
    state="$(get_warp_state)"
    [ "$state" = "$target" ] && return 0
    sleep 0.5
    elapsed=$((elapsed + 1))
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

toggle() {
  # No stdout/stderr output in toggle mode
  have_cmd warp-cli || graceful_exit "warp-cli missing"
  have_cmd notify-send || true

  local state
  state="$(get_warp_state)"

  if [ "$state" = "on" ]; then
    log "Attempting disconnect"
    notify-send "$ICON_OFF  WARP" "Disconnecting..." -u low >/dev/null 2>&1 || true

    warp-cli disconnect >/dev/null 2>&1 || true

    if wait_for_state "off"; then
      notify-send "$ICON_OFF  WARP" "Disconnected" -u low >/dev/null 2>&1 || true
      log "Disconnect successful"
    else
      notify-send "$ICON_OFF  WARP" "Failed to disconnect" -u normal >/dev/null 2>&1 || true
      log "Disconnect timeout/failure"
      warp-cli disconnect >/dev/null 2>&1 || true
    fi
  else
    log "Attempting connect"
    notify-send "$ICON_ON  WARP" "Connecting..." -u low >/dev/null 2>&1 || true

    warp-cli connect >/dev/null 2>&1 || true

    if wait_for_state "on"; then
      notify-send "$ICON_ON  WARP" "Connected" -u low >/dev/null 2>&1 || true
      log "Connect successful"
    else
      notify-send "$ICON_ON  WARP" "Failed to connect" -u normal >/dev/null 2>&1 || true
      log "Connect timeout/failure"
      warp-cli disconnect >/dev/null 2>&1 || true
    fi
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
