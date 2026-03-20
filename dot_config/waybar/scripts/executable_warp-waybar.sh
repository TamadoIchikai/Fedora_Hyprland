#!/bin/bash

ICON_ON='󰴴'
ICON_OFF='󰦜'
TIMEOUT=5
LOG_FILE="${XDG_RUNTIME_DIR}/warp-toggle.log"
STATE_FILE="${XDG_RUNTIME_DIR}/warp-state"

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to get current WARP status
get_warp_status() {
  curl -s --max-time 2 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -o 'warp=on'
}

# Function to check if WARP is actually connected
wait_for_connection() {
  local target_state="$1"
  local elapsed=0
  
  while [ $elapsed -lt $TIMEOUT ]; do
    status=$(get_warp_status)
    
    if [ "$target_state" = "on" ] && [ "$status" = "warp=on" ]; then
      log "Successfully connected to WARP"
      return 0
    elif [ "$target_state" = "off" ] && [ -z "$status" ]; then
      log "Successfully disconnected from WARP"
      return 0
    fi
    
    sleep 0.5
    elapsed=$((elapsed + 1))
  done
  
  log "Failed to reach target state: $target_state (timeout after ${TIMEOUT}s)"
  return 1
}

# Toggle mode
if [ "$1" = "toggle" ]; then
  status=$(get_warp_status)
  
  if [ "$status" = "warp=on" ]; then
    # Disconnecting
    log "Attempting to disconnect WARP"
    notify-send "$ICON_OFF  WARP" "Disconnecting..." -u low
    
    warp-cli disconnect 2>/dev/null &
    local pid=$!
    
    # Wait for disconnect with timeout
    if wait_for_connection "off"; then
      notify-send "$ICON_OFF  WARP" "Disconnected" -u low
      log "Disconnect successful"
    else
      notify-send "$ICON_OFF  WARP" "Failed to disconnect" -u critical
      warp-cli disconnect 2>/dev/null &
      log "Disconnect failed"
    fi
    
    wait $pid 2>/dev/null
  else
    # Connecting
    log "Attempting to connect WARP"
    notify-send "$ICON_ON  WARP" "Connecting..." -u low
    
    warp-cli connect 2>/dev/null &
    local pid=$!
    
    # Wait for connect with timeout
    if wait_for_connection "on"; then
      notify-send "$ICON_ON  WARP" "Connected" -u low
      log "Connect successful"
    else
      notify-send "$ICON_ON  WARP" "Failed to connect" -u critical
      warp-cli disconnect 2>/dev/null &
      log "Connect failed"
    fi
    
    wait $pid 2>/dev/null
  fi
  
  exit 0
fi

# Default output for Waybar
status=$(get_warp_status)

if [ "$status" = "warp=on" ]; then
  echo '{"text": "'"$ICON_ON"'", "tooltip": "WARP: Connected", "class": "connected"}'
else
  echo '{"text": "'"$ICON_OFF"'", "tooltip": "WARP: Disconnected", "class": "disconnected"}'
fi
