#!/usr/bin/env bash
set -euo pipefail

# Paths to default system sounds
SOUND_ADD="${HOME}/.local/share/sounds/USB_Connect.mp3"
SOUND_REMOVE="${HOME}/.local/share/sounds/USB_Disconnect.mp3"

# The command to play the audio
PLAYER="paplay --volume=65536"

# Increased cooldown to 2 seconds to prevent slow-hardware double triggers
COOLDOWN=2

last_add=0
last_remove=0

# --- Initialization & Checks ---
HAS_NOTIFY=0
if command -v notify-send >/dev/null 2>&1; then
    HAS_NOTIFY=1
else
    echo "Warning: 'notify-send' command not found. Desktop notifications are disabled."
fi

# --- Safe Exit Handler ---
cleanup() {
    echo ""
    echo "Shutting down USB monitor"
    exit 0
}

trap cleanup SIGINT SIGTERM

# --- Notification Handler ---
notify_event() {
    local event_type="$1"
    
    # Only execute if the startup check passed
    if (( HAS_NOTIFY == 1 )); then
        if [[ "$event_type" == "add" ]]; then
            notify-send -u low -t 2000 -i device_usb "USB Device" "Connected" &
        elif [[ "$event_type" == "remove" ]]; then
            notify-send -u low -t 2000 -i mkusb "USB Device" "Disconnected" &
        fi
    fi
}

echo "Listening for USB connect/disconnect events... (Press Ctrl+C to stop)"

# Monitor only udev events (ignore raw kernel noise) and filter for USBs
udevadm monitor --udev --subsystem-match=usb | while read -r line; do
    if [[ "$line" == *"add"* ]]; then
        current_time=$(date +%s)
        
        # Only play and notify if the cooldown period has passed
        if (( current_time - last_add >= COOLDOWN )); then
            $PLAYER "$SOUND_ADD" &
            notify_event "add"
            last_add=$current_time
        fi
    elif [[ "$line" == *"remove"* ]]; then
        current_time=$(date +%s)
        
        if (( current_time - last_remove >= COOLDOWN )); then
            $PLAYER "$SOUND_REMOVE" &
            notify_event "remove"
            last_remove=$current_time
        fi
    fi
done
