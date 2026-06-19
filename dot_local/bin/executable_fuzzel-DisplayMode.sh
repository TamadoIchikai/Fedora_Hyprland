#!/usr/bin/env bash
set -uo pipefail

# 1. Dependency check
command -v jq >/dev/null || { notify-send "Display Error" "jq is required." -u critical; exit 1; }
command -v hyprctl >/dev/null || { notify-send "Display Error" "hyprctl not found." -u critical; exit 1; }

# 2. Ingest Variables
LAPTOP="${LAPTOP_OUTPUT:-eDP-1}"
EXTERNAL="${EXTERNAL_OUTPUT:-HDMI-A-1}"
LAPTOP_MODE="${LAPTOP_MODE:-1920x1080@60}"
EXTERNAL_MODE="${EXTERNAL_MODE:-1920x1080@60}"
LAPTOP_POS="${LAPTOP_POS:-0x0}"
EXTERNAL_POS_EXTEND="${EXTERNAL_POS_EXTEND:-1920x0}"
EXTERNAL_POS_MIRROR="${EXTERNAL_POS_MIRROR:-0x0}"
LAPTOP_SCALE="${LAPTOP_SCALE:-1}"
EXTERNAL_SCALE="${EXTERNAL_SCALE:-1}"

# 3. Lua-Native Safe switching functions
enable_monitor() {
    local out
    local mirror_str=""
    
    if [[ $# -eq 5 && -n "$5" ]]; then
        mirror_str=", mirror = '$5'"
    fi
    
    local lua_cmd="hl.monitor({ output = '$1', mode = '$2', position = '$3', scale = $4, disabled = false${mirror_str} })"
    
    out=$(hyprctl eval "$lua_cmd" 2>&1) || true
    
    if [[ "$out" != "ok" && "$out" != *"ok"* && -n "$out" ]]; then
        notify-send "Hyprctl Enable Error ($1)" "$out" -u critical || true
    fi
    
    hyprctl dispatch dpms on "$1" >/dev/null 2>&1 || true
}

disable_monitor() {
    local out
    local lua_cmd="hl.monitor({ output = '$1', disabled = true })"
    
    out=$(hyprctl eval "$lua_cmd" 2>&1) || true
    
    if [[ "$out" != "ok" && "$out" != *"ok"* && -n "$out" ]]; then
        notify-send "Hyprctl Disable Error ($1)" "$out" -u critical || true
    fi
    
    hyprctl dispatch dpms off "$1" >/dev/null 2>&1 || true
}

verify_active() {
    sleep 1 
    local active_monitors
    active_monitors=$(hyprctl monitors -j 2>/dev/null || echo "[]") 
    if jq -e ".[] | select(.name == \"$1\")" <<< "$active_monitors" >/dev/null; then
        return 0 
    else
        return 1 
    fi
}

# ---------------------------------------------------------
# 4. EMERGENCY RESCUE HATCH (Prevents the "Blind State")
# ---------------------------------------------------------
# Check how many monitors are actively rendering right now
active_monitors_count=$(jq length <<< "$(hyprctl monitors -j 2>/dev/null || echo "[]")")

# If user passed 'rescue' argument OR if 0 monitors are rendering:
if [[ "${1:-}" == "rescue" ]] || [[ "$active_monitors_count" -eq 0 ]]; then
    enable_monitor "$LAPTOP" "$LAPTOP_MODE" "$LAPTOP_POS" "$LAPTOP_SCALE"
    notify-send "Display Rescue" "Emergency override triggered. Laptop screen restored." -u critical || true
    exit 0
fi
# ---------------------------------------------------------

# 5. Check for physical connections
monitors_all_json=$(hyprctl monitors all -j 2>/dev/null || echo "[]")
laptop_connected=$(jq -r ".[] | select(.name == \"$LAPTOP\") | .name" <<< "$monitors_all_json")
external_connected=$(jq -r ".[] | select(.name == \"$EXTERNAL\") | .name" <<< "$monitors_all_json")

# 6. Show Menu 
SELECTION=$(printf "󰍹  - Extend (Dual Monitor)\n󰌢  - Internal Screen Only\n󰍺  - External Screen Only\n󰍺  - Mirror Displays" \
            | fuzzel --dmenu -l 4 -p "Display Mode:  " || true)

if [[ -z "$SELECTION" ]]; then
    exit 0
fi

# 7. Execute Logic
case "$SELECTION" in
    *"Extend"*)
        if [[ -n "$laptop_connected" ]]; then enable_monitor "$LAPTOP" "$LAPTOP_MODE" "$LAPTOP_POS" "$LAPTOP_SCALE"; fi
        if [[ -n "$external_connected" ]]; then enable_monitor "$EXTERNAL" "$EXTERNAL_MODE" "$EXTERNAL_POS_EXTEND" "$EXTERNAL_SCALE"; fi
        notify-send "Display Mode" "Extended to both displays" -i video-display
        ;;
        
    *"Internal Screen Only"*)
        if [[ -z "$laptop_connected" ]]; then
            notify-send "Display Error" "Internal screen not found! Aborting to prevent blind state." -u critical
            exit 1
        fi
        enable_monitor "$LAPTOP" "$LAPTOP_MODE" "$LAPTOP_POS" "$LAPTOP_SCALE"
        if verify_active "$LAPTOP"; then
            if [[ -n "$external_connected" ]]; then disable_monitor "$EXTERNAL"; fi
            notify-send "Display Mode" "Internal screen only" -i video-display
        else
            notify-send "Display Error" "Internal screen failed to wake up. Aborting." -u critical
        fi
        ;;
        
    *"External Screen Only"*)
        if [[ -z "$external_connected" ]]; then
            notify-send "Display Error" "External screen not connected! Aborting." -u critical
            exit 1
        fi
        enable_monitor "$EXTERNAL" "$EXTERNAL_MODE" "$EXTERNAL_POS_EXTEND" "$EXTERNAL_SCALE"
        if verify_active "$EXTERNAL"; then
            if [[ -n "$laptop_connected" ]]; then disable_monitor "$LAPTOP"; fi
            notify-send "Display Mode" "External screen only" -i video-display
        else
            notify-send "Display Error" "External screen failed to wake up. Aborting to prevent blind state." -u critical
        fi
        ;;
        
    *"Mirror Displays"*)
        if [[ -n "$laptop_connected" ]]; then 
            enable_monitor "$LAPTOP" "$LAPTOP_MODE" "$LAPTOP_POS" "$LAPTOP_SCALE"
        fi
        if [[ -n "$external_connected" && -n "$laptop_connected" ]]; then 
            enable_monitor "$EXTERNAL" "$EXTERNAL_MODE" "$EXTERNAL_POS_MIRROR" "$EXTERNAL_SCALE" "$LAPTOP"
        fi
        notify-send "Display Mode" "Displays mirrored" -i video-display
        ;;
esac
