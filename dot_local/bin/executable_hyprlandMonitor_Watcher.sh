#!/usr/bin/env bash
set -u

# Locate the Hyprland IPC Socket
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    echo "Error: HYPRLAND_INSTANCE_SIGNATURE is not set. Are you running this inside Hyprland?"
    exit 1
fi

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
if [[ ! -S "$SOCKET" ]]; then
    SOCKET="/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
fi

echo "Listening to Hyprland socket: $SOCKET..."

# Listen to hardware events continuously via socat
socat -U - UNIX-CONNECT:"$SOCKET" | while read -r line; do
    
    # Trigger on ANY monitor connection change
    if [[ "$line" == *"monitorremoved"* ]] || [[ "$line" == *"monitoradded"* ]]; then
        
        echo "Hardware event detected: $line"
        
        # Give Hyprland and DRM 1 full second to settle the hardware interrupt
        sleep 1
        
        # Query active monitors (only returns monitors actively rendering)
        active_count=$(hyprctl monitors -j 2>/dev/null | jq length)
        
        echo "Active monitors rendering: $active_count"
        
        # If we hit the "Blind State" (0 monitors rendering)
        if [[ "$active_count" -eq 0 ]]; then
            echo "Blind state detected! Executing emergency rescue..."
            
            # THE FIX: Force a complete DRM reprobe and config reset
            hyprctl reload >/dev/null 2>&1
            
            # Fallback DPMS kick just to be absolutely certain the backlight turns on
            LAPTOP="${LAPTOP_OUTPUT:-eDP-1}"
            hyprctl dispatch dpms on "$LAPTOP" >/dev/null 2>&1
            
            # Notify
            notify-send -u normal -t 3000 "Auto Rescue" "Displays disconnected. Config reloaded to restore laptop screen."
        fi
    fi
done
