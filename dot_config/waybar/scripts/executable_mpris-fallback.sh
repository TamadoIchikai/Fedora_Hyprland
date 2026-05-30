#!/usr/bin/env bash

# Quiet, Waybar-safe fallback for when no media is playing.
# - never prints errors
# - always exits 0
# - prints either "" (hide) or the fallback text

FALLBACK_TEXT='[ 󰝛  No media playing ]'

# If playerctl isn't installed, just show fallback (but don't error).
command -v playerctl >/dev/null 2>&1 || { printf '%s\n' "$FALLBACK_TEXT"; exit 0; }

# Hide fallback ONLY when some MPRIS player is actively Playing.
# Otherwise, show fallback.
if playerctl status 2>/dev/null | grep -qx "Playing"; then
  printf '\n'
else
  printf '%s\n' "$FALLBACK_TEXT"
fi

exit 0
