#!/usr/bin/env bash
# colorpicker.sh - pick a color with hyprpicker and copy to clipboard
set -euo pipefail

# Pick color (support both 6- and 8-digit HEX)
color=$(hyprpicker | grep -oE '#[0-9A-Fa-f]{6,8}')

# Exit if no color selected
[ -z "$color" ] && exit 0

# Copy to clipboard
echo -n "$color" | wl-copy

# Convert HEX to RGB and HSL using an embedded Python script
mapfile -t conversions < <(python3 -c "
import sys, colorsys
c = sys.argv[1].lstrip('#')
lv = len(c)

# Parse HEX into RGB and Alpha
r, g, b = int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
a = round(int(c[6:8], 16) / 255.0, 2) if lv == 8 else 1.0

# Convert RGB to HSL
h, l, s = colorsys.rgb_to_hls(r/255.0, g/255.0, b/255.0)
h, s, l = round(h*360), round(s*100), round(l*100)

if lv == 8:
    print(f'rgba({r}, {g}, {b}, {a})')
    print(f'hsla({h}, {s}%, {l}%, {a})')
else:
    print(f'rgb({r}, {g}, {b})')
    print(f'hsl({h}, {s}%, {l}%)')
" "$color")

rgb="${conversions[0]}"
hsl="${conversions[1]}"

# Show notification with color preview
notify-send "🎨 Color Copied" "<b>HEX:</b> $color\n<b>RGB:</b> $rgb\n<b>HSL:</b> $hsl" \
  -h string:x-canonical-private-synchronous:colorcopy \
  -h "int:transient:1" \
  -h "string:bgcolor:$color"
