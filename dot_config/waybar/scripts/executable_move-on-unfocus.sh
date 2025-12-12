#!/usr/bin/env bash
# Move specific apps to workspace 10 when they are not focused.

apps=("org.pulseaudio.pavucontrol" "blueman-manager")

while true; do
  focused_class=$(hyprctl activewindow -j | jq -r '.class // empty' 2>/dev/null)

  for app in "${apps[@]}"; do
    # For each matching window, if it's not focused and not already on workspace 10, move it.
    hyprctl clients -j | jq -r '.[] | @base64' | while read -r line; do
      _jq() { echo "$line" | base64 --decode | jq -r "$1"; }
      cls=$(_jq '.class')
      addr=$(_jq '.address')
      ws=$(_jq '.workspace.id')

      if [[ "$cls" == "$app" ]] && [[ "$ws" != "10" ]] && [[ "$cls" != "$focused_class" ]]; then
        hyprctl dispatch movetoworkspacesilent "10,address:$addr" >/dev/null 2>&1
      fi
    done
  done

  sleep 0.3
done
