#!/usr/bin/env bash
set -uo pipefail
source "$HOME/.config/abstractions/wm.sh"

# ---------------------------------------------------------
# 0. Argument Parsing & Help Menu
# ---------------------------------------------------------
MODE_ARG=""
USE_FUZZEL=false

show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "A script to manage Hyprland monitor layouts."
    echo ""
    echo "Options:"
    echo "  --fuzzel                 Open the graphical Fuzzel interactive menu"
    echo "  --mode <mode>            Manually set display mode (laptop, external, extend, mirror)"
    echo "  -h, --help               Show this help message"
    echo ""
    exit 0
}

# If no arguments are passed, show help and exit
if [[ $# -eq 0 ]]; then
    show_help
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            if [[ -n "${2:-}" ]]; then
                MODE_ARG="${2,,}" # Convert to lowercase for safety
                shift 2
            else
                echo "Error: --mode requires an argument (laptop/external/extend/mirror)" >&2
                exit 1
            fi
            ;;
        --fuzzel)
            USE_FUZZEL=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            echo "Run '$(basename "$0") --help' for usage instructions." >&2
            exit 1
            ;;
    esac
done

# 1. Dependency check
command -v jq >/dev/null || { echo "Error: jq not found" >&2; exit 1; }

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

# 3. Safe switching functions (compositor-agnostic)
# enable_monitor <name> <mode> <pos> <scale> [mirror-of]
enable_monitor() {
    if ! WM_monitor_enable "$@"; then
        notify-send "Monitor Enable Error ($1)" "failed to enable $1" -u critical || true
    fi
}

disable_monitor() {
    if ! WM_monitor_disable "$1"; then
        notify-send "Monitor Disable Error ($1)" "failed to disable $1" -u critical || true
    fi
}

verify_active() {
    sleep 1
    WM_monitor_list 2>/dev/null | jq -e --arg m "$1" 'any(.[]; .name == $m)' >/dev/null
}

# 4. Check for physical connections
monitors_all_json=$(WM_monitor_list --all 2>/dev/null || echo "[]")
laptop_connected=$(jq -r ".[] | select(.name == \"$LAPTOP\") | .name" <<< "$monitors_all_json")
external_connected=$(jq -r ".[] | select(.name == \"$EXTERNAL\") | .name" <<< "$monitors_all_json")

# 5. Show Menu OR Process CLI Flag
SELECTION=""

if [[ "$USE_FUZZEL" == true ]]; then
    # Launch Fuzzel if --fuzzel was explicitly passed
    SELECTION=$(printf "󰍹  - Extend (Dual Monitor)\n󰌢  - Internal Screen Only\n󰍺  - External Screen Only\n󰍺  - Mirror Displays" \
                | fuzzel --dmenu -l 4 -p "Display Mode:  " || true)
elif [[ -n "$MODE_ARG" ]]; then
    # Map the CLI argument to the selection strings
    case "$MODE_ARG" in
        laptop)   SELECTION="Internal Screen Only" ;;
        external) SELECTION="External Screen Only" ;;
        extend)   SELECTION="Extend" ;;
        mirror)   SELECTION="Mirror Displays" ;;
        *)
            echo "Error: Invalid mode: $MODE_ARG. Use laptop, external, extend, or mirror." >&2
            exit 1
            ;;
    esac
fi

if [[ -z "$SELECTION" ]]; then
    exit 0
fi

# 6. Execute Logic
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
