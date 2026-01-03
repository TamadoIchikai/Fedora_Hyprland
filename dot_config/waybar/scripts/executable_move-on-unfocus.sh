#!/usr/bin/env bash
# Move specific apps to workspace 10 when they are not focused.

apps=("org.pulseaudio.pavucontrol" "blueman-manager")

declare -A last_focus_time
grace_ms=650

now_ms() { date +%s%3N; }

while true; do
  focused_class=$(hyprctl activewindow -j | jq -r '.class // empty' 2>/dev/null)
  now=$(now_ms)

  # Record the time the focused class was seen
  if [[ -n "$focused_class" ]]; then
    last_focus_time["$focused_class"]=$now
  fi

  for app in "${apps[@]}"; do
    hyprctl clients -j | jq -r '.[] | @base64' | while read -r line; do
      _jq() { echo "$line" | base64 --decode | jq -r "$1"; }
      cls=$(_jq '.class')
      addr=$(_jq '.address')
      ws=$(_jq '.workspace.id')

      # Skip if it was just focused recently (avoid immediate yank-back)
      last=${last_focus_time["$cls"]:-0}
      if (( now - last < grace_ms )); then
        continue
      fi

      if [[ "$cls" == "$app" ]] && [[ "$ws" != "10" ]] && [[ "$cls" != "$focused_class" ]]; then
        hyprctl dispatch movetoworkspacesilent "10,address:$addr" >/dev/null 2>&1
      fi
    done
  done

  sleep 0.3
done
