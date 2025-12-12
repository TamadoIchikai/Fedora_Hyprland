#!/bin/bash

APP_CLASS="$1"
LAUNCH_CMD="$2"

# Find an existing window by class
window_addr=$(hyprctl clients -j | jq -r ".[] | select(.class==\"$APP_CLASS\") | .address" | head -n1)
current_ws=$(hyprctl activeworkspace -j | jq -r '.id')

if [ -z "$window_addr" ]; then
  # Not running: start it on workspace 10, then bring to current workspace
  hyprctl dispatch exec "[workspace 10 silent] $LAUNCH_CMD"
  sleep 0.4
  window_addr=$(hyprctl clients -j | jq -r ".[] | select(.class==\"$APP_CLASS\") | .address" | head -n1)
  if [ -n "$window_addr" ]; then
    hyprctl dispatch movetoworkspace "$current_ws,address:$window_addr"
    hyprctl dispatch focuswindow "address:$window_addr"
  fi
  exit 0
fi

# If running, toggle between workspace 10 and current
app_ws=$(hyprctl clients -j | jq -r ".[] | select(.class==\"$APP_CLASS\") | .workspace.id" | head -n1)

if [ "$app_ws" = "$current_ws" ]; then
  hyprctl dispatch movetoworkspacesilent "10,address:$window_addr"
else
  hyprctl dispatch movetoworkspace "$current_ws,address:$window_addr"
  hyprctl dispatch focuswindow "address:$window_addr"
fi
