#!/usr/bin/env bash
# colorpicker.sh — pick a color with hyprpicker and copy to clipboard

# Pick color (support both 6- and 8-digit HEX)
color=$(hyprpicker | grep -oE '#[0-9A-Fa-f]{6,8}')

# Exit if no color selected
[ -z "$color" ] && exit 0

# Copy to clipboard
echo -n "$color" | wl-copy

# Show notification with color preview
notify-send "🎨 Color Copied" "$color" \
  -h string:x-canonical-private-synchronous:colorcopy \
  -h "int:transient:1" \
  -h "string:bgcolor:$color"

