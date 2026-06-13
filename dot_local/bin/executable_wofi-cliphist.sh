#!/usr/bin/env bash
set -euo pipefail

# --- Auto-Paste Setup Functions ---

get_active_window_json() {
    hyprctl activewindow -j 2>/dev/null || printf '{}'
}

get_focused_app_id() {
    get_active_window_json |
        jq -r '(.class // .initialClass // "") | ascii_downcase'
}

get_focused_window_address() {
    get_active_window_json |
        jq -r '(.address // "")'
}

notify_skip() {
    local msg="$1"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u low "Cliphist paste skipped" "$msg"
    fi
}

paste_to_app() {
    local app_id="${1:-}"

    case "$app_id" in
        foot|kitty|alacritty|wezterm|org.wezfurlong.wezterm|ghostty|com.mitchellh.ghostty)
            # Ctrl+Shift+V, then release Shift/Ctrl
            wtype -M ctrl -M shift -P v -p v -m shift -m ctrl
            ;;
        *)
            # Ctrl+V, then release Ctrl
            wtype -M ctrl -P v -p v -m ctrl
            ;;
    esac

    # Kill leftover wtype only if something weird remains.
    pkill -x wtype 2>/dev/null || true
}

wait_until_target_window_focused() {
    local target_address="$1"

    # Wait up to 1 second for focus to return to the original window.
    for _ in {1..20}; do
        sleep 0.05
        current_address="$(get_focused_window_address)"

        if [[ "$current_address" == "$target_address" ]]; then
            return 0
        fi
    done

    return 1
}

# Capture target window details BEFORE opening wofi
target_app="$(get_focused_app_id)"
target_address="$(get_focused_window_address)"

if [[ -z "$target_address" || "$target_address" == "null" ]]; then
    notify_skip "No focused target window found."
    exit 0
fi


# --- Original cliphist-wofi logic ---

# set up thumbnail directory
thumb_dir="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/thumbs"
mkdir -p "$thumb_dir"

cliphist_list="$(cliphist list)"

# delete thumbnails in cache but not in cliphist
# use nullglob so the loop doesn't run literally on "$thumb_dir/*" if empty
shopt -s nullglob
for thumb in "$thumb_dir"/*; do
    clip_id="${thumb##*/}"
    clip_id="${clip_id%.*}"
    check=$(rg <<< "$cliphist_list" "^$clip_id\s" || true)
    if [ -z "$check" ]; then
        >&2 rm -v "$thumb"
    fi
done
shopt -u nullglob

# remove unnecessary image tags
# create thumbnail if image not processed already
# print escape sequence
read -r -d '' prog <<EOF || true
/^[0-9]+\s<meta http-equiv=/ { next }
match(\$0, /^([0-9]+)\s(\[\[\s)?binary.*(jpg|jpeg|png|bmp)/, grp) {
    image = grp[1]"."grp[3]
    system("[ -f $thumb_dir/"image" ] || echo " grp[1] "\\\\\t | cliphist decode | magick - -resize '256x256>' $thumb_dir/"image )
    print "img:$thumb_dir/"image
    next
}
1
EOF

# DIRTY FIX: Prepend a dummy text item so Wofi measures a text row first.
# We use a smart background job that waits for Hyprland to focus Wofi before pressing Down.
(
    for _ in {1..30}; do
        if pgrep -x wofi >/dev/null; then
            sleep 0.2 # Tiny buffer to ensure Wofi's input engine is ready
            wtype -k Down
            break
        fi
        sleep 0.05
    done
) &
choice=$( (echo "[ Clipboard History ]"; gawk <<< "$cliphist_list" "$prog") | wofi -I --dmenu --cache-file=/dev/null -Dimage_size=200 -Dynamic_lines=true)


# Stop execution if nothing selected in wofi menu
[ -z "$choice" ] && exit 1

# DIRTY FIX: Exit silently without copying or pasting if the dummy item is selected.
[ "$choice" = "[ Clipboard History ]" ] && exit 0

if [ "${choice::4}" = "img:" ]; then
    # It's an image: Wofi outputs "img:/path/to/1234.png"
    thumb_file="${choice:4}"
    filename="${thumb_file##*/}"  # Extracts "1234.png"
    clip_id="${filename%.*}"      # Extracts "1234"
    img_ext="${filename##*.}"     # Extracts "png"

    # Map the extension to the exact MIME type wl-copy needs
    case "$img_ext" in
        jpg|jpeg) mime_type="image/jpeg" ;;
        png)      mime_type="image/png" ;;
        bmp)      mime_type="image/bmp" ;;
        *)        mime_type="image/png" ;; # Fallback
    esac

    # Decode image using ID (with a tab character so cliphist matches exactly)
    # and explicitly tell wl-copy it's an image.
    printf "%s\t" "$clip_id" | cliphist decode | wl-copy --type "$mime_type"
else
    # It's text: Wofi outputs the full line e.g., "1234\tCopied text here"
    printf "%s" "$choice" | cliphist decode | wl-copy
fi

# --- Auto-Paste Execution ---

# Wait for focus to return to the original window, then trigger the paste
if wait_until_target_window_focused "$target_address"; then
    sleep 0.08
    paste_to_app "$target_app"
else
    notify_skip "Focus did not return to the original window."
fi
