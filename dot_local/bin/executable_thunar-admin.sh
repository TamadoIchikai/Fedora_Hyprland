#!/usr/bin/env bash
# Open a directory as admin in Thunar (gvfs admin://). After the window closes
# and polkit's cached authorization expires, restart the MATE polkit agent so
# its stale key icons disappear from the waybar tray.

dir="${1:-$PWD}"
agent=/usr/libexec/polkit-mate-authentication-agent-1
state="${XDG_RUNTIME_DIR:-/tmp}/thunar-admin"
mkdir -p "$state"
touch "$state/$$"

list_thunar() {
  hyprctl clients -j | jq -r '.[] | select(.class|test("^thunar$";"i")) | .address' | sort
}

before=$(list_thunar)
thunar "admin://$dir" &

# Find the new window (wait up to ~60s to allow for the password prompt)
win=""
for _ in $(seq 1 120); do
  sleep 0.5
  win=$(comm -13 <(echo "$before") <(list_thunar) | head -n1)
  [[ -n $win ]] && break
done

# Wait for that window to close
if [[ -n $win ]]; then
  while list_thunar | grep -qx "$win"; do sleep 1; done
fi

rm -f "$state/$$"

# Skip cleanup while another admin window opened by this script is still alive
for f in "$state"/*; do
  [[ -e $f ]] || continue
  if kill -0 "$(basename "$f")" 2>/dev/null; then
    exit 0
  fi
  rm -f "$f"  # stale entry
done

# Let polkit's cached authorization (~5 min) expire naturally so Thunar
# doesn't re-prompt, then restart the agent to clear the stale key icon(s).
while [[ -n $(pkcheck --list-temp 2>/dev/null) ]]; do sleep 5; done
pkill -f "$agent"
sleep 0.3
setsid -f "$agent" >/dev/null 2>&1
