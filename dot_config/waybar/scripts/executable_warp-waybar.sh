#!/bin/bash

ICON_ON='󰴴'
ICON_OFF='󰦜'

# Toggle mode
if [ "$1" = "toggle" ]; then
  status=$(curl -s https://www.cloudflare.com/cdn-cgi/trace/ | grep -o 'warp=on')
  if [ "$status" = "warp=on" ]; then
    warp-cli disconnect
    notify-send "$ICON_OFF  WARP" "Disconnected"
  else
    warp-cli connect
    notify-send "$ICON_ON  WARP" "Connected"
  fi
  exit 0
fi

# Default output for Waybar
status=$(curl -s --max-time 2 https://www.cloudflare.com/cdn-cgi/trace/ | grep -o 'warp=on')
if [ "$status" = "warp=on" ]; then
  echo '{"text": "'"$ICON_ON"'", "tooltip": "WARP:  Connected", "class": "connected"}'
else
  echo '{"text": "'"$ICON_OFF"'", "tooltip": "WARP: Disconnected", "class": "disconnected"}'
fi
