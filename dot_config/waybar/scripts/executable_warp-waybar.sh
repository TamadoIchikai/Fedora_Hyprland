#!/usr/bin/env bash

# Waybar-safe Cloudflare WARP toggle/status
# - default mode prints ONLY JSON and exits 0
# - toggle mode is quiet (no stdout/stderr) and exits 0
# - logs to a file; optional DEBUG=1 for extra logs

# -e is intentionally omitted (we never want a hard-fail inside a Waybar
# click handler); -u catches undefined variables; -o pipefail propagates
# a nonzero exit from any stage of a pipeline (e.g. a curl killed mid-
# transfer leaves grep operating on incomplete output — we want to see that).
set -uo pipefail

# Pin PATH so a compromised/writable PATH entry can't substitute the tools
# this script shells out to (curl, warp-cli, notify-send).
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ICON_ON='󰴴'
ICON_OFF='󰦜'
ICON_UNKNOWN='󰲛'
TIMEOUT=5

# Systemd services stopped/started when the tunnel is idle/needed.
WARP_SVC="warp-svc.service"                    # root daemon (system unit)
WARP_DESKTOP_SVC="warp-desktop-svc.service"    # desktop helper (user unit)
SVC_START_TIMEOUT=10                           # daemon readiness wait (seconds)

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
  # Prefer the daemon's own connection report (local Unix-socket IPC,
  # ~4ms) over a full HTTPS round-trip to cloudflare.com (~155ms), which
  # Waybar's status polling would otherwise pay on every refresh.
  local warp
  if warp="$(warp-cli status 2>/dev/null)"; then
    case "$warp" in
      *"Status: Connected"*) printf 'on';  return 0 ;;
      *"Status:"*)           printf 'off'; return 0 ;;
    esac
  fi

  # Daemon unreachable, or its output format is unrecognized: fall back to
  # the end-to-end routing probe (unchanged behavior).
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

daemon_active() {
  systemctl is-active --quiet "$WARP_SVC" 2>/dev/null
}

daemon_ready() {
  warp-cli status >/dev/null 2>&1
}

# Poll until warp-cli can reach the daemon (socket up).
wait_for_daemon() {
  local deadline=$(( SECONDS + SVC_START_TIMEOUT ))
  while [ "$SECONDS" -lt "$deadline" ]; do
    daemon_ready && return 0
    sleep 0.5
  done
  return 1
}

start_warp_services() {
  # Root daemon first (requires the scoped NOPASSWD sudoers rule).
  if ! daemon_active; then
    have_cmd sudo && sudo -n systemctl start "$WARP_SVC" >/dev/null 2>&1 || return 1
  fi

  wait_for_daemon

  # User-level desktop helper; best-effort (no root needed).
  have_cmd systemctl && systemctl --user start "$WARP_DESKTOP_SVC" >/dev/null 2>&1 || true
  daemon_ready
}

stop_warp_services() {
  # Desktop helper first, then the root daemon.
  have_cmd systemctl && systemctl --user stop "$WARP_DESKTOP_SVC" >/dev/null 2>&1 || true
  have_cmd sudo && sudo -n systemctl stop "$WARP_SVC" >/dev/null 2>&1 || true
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
  local target="$1" icon active ok
  if [ "$target" = "on" ]; then
    icon="$ICON_ON"
    active="Connect"
  else
    icon="$ICON_OFF"
    active="Disconnect"
  fi

  log "Attempting $active"
  notify-send "$icon  WARP" "$active..." -u low >/dev/null 2>&1 || true

  if [ "$target" = "on" ]; then
    if start_warp_services && warp-cli connect >/dev/null 2>&1; then
      wait_for_state on && ok=1 || ok=0
    else
      ok=0
    fi
  else
    # Graceful teardown: disconnect first, then stop the background services.
    warp-cli disconnect >/dev/null 2>&1 || true
    if wait_for_state off; then
      stop_warp_services
      ok=1
    else
      ok=0
    fi
  fi

  if [ "$ok" = "1" ]; then
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
    set_target_state "off"
  else
    set_target_state "on"
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
