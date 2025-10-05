#!/bin/bash

if playerctl status &>/dev/null; then
  # When a player is active, hide this module
  echo ""
else
  # No player → show fallback
  echo "[ 󰝛  No media playing ]"
fi
