#!/usr/bin/env bash

# Quiet, Waybar-safe fallback for when no MPRIS player is running.
# - never prints errors
# - always exits 0
# - prints either "" (hide) or the fallback text

FALLBACK_TEXT='[ 󰝛  No media playing ]'

# If playerctl isn't installed, just show fallback (but don't error).
command -v playerctl >/dev/null 2>&1 || { printf '%s\n' "$FALLBACK_TEXT"; exit 0; }

# If any player is present, hide fallback.
# Prefer checking the player list rather than `playerctl status` (which can emit errors)
# and can be non-zero for reasons other than "no player".
if playerctl -l >/dev/null 2>&1 && [ -n "$(playerctl -l 2>/dev/null | head -n1)" ]; then
  printf '\n'
else
  printf '%s\n' "$FALLBACK_TEXT"
fi

exit 0
