#!/bin/bash

get_devices() {
  kdeconnect-cli -a | sed -E 's/ \((.*)\)//'
}

# Default output for Waybar
if [ -z "$1" ]; then
  devices=$(get_devices)
  if [ -z "$devices" ]; then
    echo '{"text": "", "tooltip": "No connected devices", "class": "disconnected"}'
  else
    tooltip=$(echo "$devices" | awk -F: '{print $1}' | paste -sd ", ")
    echo "{\"text\": \"\", \"tooltip\": \"Connected: $tooltip\", \"class\": \"connected\"}"
  fi
    exit 0
fi

case "$1" in
  clipboard)
    devices=$(kdeconnect-cli -a --id-only)
    if [ -z "$devices" ]; then
      notify-send "KDE Connect" "No connected devices"
      exit 1
    fi

    text=$(wl-paste 2>/dev/null || xclip -o -selection clipboard 2>/dev/null)
    if [ -n "$text" ]; then
      for dev in $devices; do
        kdeconnect-cli --device "$dev" --share-text "$text"
      done
      preview=$(echo "$text" | head -c 100)
      notify-send "KDE Connect" "Clipboard sent: $preview"
    else
      notify-send "KDE Connect" "Clipboard is empty"
    fi
    ;;
  file)
    devices=$(kdeconnect-cli -a --id-only)
    if [ -z "$devices" ]; then
      notify-send "KDE Connect" "No connected devices"
      exit 1
    fi

    file=$(zenity --file-selection --title="Files")
    [ -z "$file" ] && exit 0

    dev_line=$(kdeconnect-cli -a | sed -E 's/ \((.*)\)//')
    dev=$(echo "$dev_line" | \
      zenity --list --title="Devices" --column="Device" --column="ID" | \
      awk -F: '{print $2}' | xargs)

    [ -z "$dev" ] && exit 0

    kdeconnect-cli --device "$dev" --share "$file"
    notify-send "KDE Connect" "File sent: $(basename "$file") → device $dev"
    ;;
esac
