#!/usr/bin/env bash
#
# hyprland/monitor.sh — Hyprland monitor operations.

# List monitors. `--all` includes disabled/inactive outputs.
WM_monitor_list() {
    if [ "${1:-}" = "--all" ]; then
        hyprctl monitors all -j
    else
        hyprctl monitors -j
    fi
}

WM_monitor_focused() {
    hyprctl monitors -j | jq -r '[.[] | select(.focused == true)][0].name // empty'
}

# Number of currently active (rendering) monitors.
WM_monitor_active_count() {
    hyprctl monitors -j | jq -r 'length'
}

# True if the output is known to Hyprland (active or disabled).
WM_monitor_present() {
    local name="$1"
    [ -n "$name" ] || { WM_err "WM_monitor_present: missing name"; return 1; }
    hyprctl monitors all -j | jq -e --arg m "$name" 'any(.[]; .name == $m)' >/dev/null
}

# WM_monitor_enable <name> [mode] [pos] [scale] [mirror-of]
# mode/pos/scale are optional: omitted ones are left untouched (used to
# force-enable an output without resetting its mode).
WM_monitor_enable() {
    local name="$1" mode="${2:-}" pos="${3:-}" scale="${4:-}" mirror="${5:-}" rc
    [ -n "$name" ] || { WM_err "WM_monitor_enable: missing name"; return 1; }
    WM_monitor_name_valid "$name" || { WM_err "WM_monitor_enable: invalid name '$name'"; return 1; }
    [ -z "$mode" ]   || WM_mode_valid "$mode"           || { WM_err "WM_monitor_enable: invalid mode '$mode'"; return 1; }
    [ -z "$pos" ]    || WM_mode_valid "$pos"            || { WM_err "WM_monitor_enable: invalid position '$pos'"; return 1; }
    [ -z "$scale" ]  || WM_number_valid "$scale"        || { WM_err "WM_monitor_enable: invalid scale '$scale'"; return 1; }
    [ -z "$mirror" ] || WM_monitor_name_valid "$mirror" || { WM_err "WM_monitor_enable: invalid mirror '$mirror'"; return 1; }

    local lua="hl.monitor({ output = '$name', disabled = false"
    [ -n "$mode" ]   && lua="$lua, mode = '$mode'"
    [ -n "$pos" ]    && lua="$lua, position = '$pos'"
    [ -n "$scale" ]  && lua="$lua, scale = $scale"
    [ -n "$mirror" ] && lua="$lua, mirror = '$mirror'"
    lua="$lua })"

    hyprctl eval "$lua" >/dev/null
    rc=$?
    hyprctl eval "hl.dispatch(hl.dsp.dpms({ action = 'on', monitor = '$name' }))" >/dev/null 2>&1 || true
    return "$rc"
}

WM_monitor_disable() {
    local name="$1"
    [ -n "$name" ] || { WM_err "WM_monitor_disable: missing name"; return 1; }
    WM_monitor_name_valid "$name" || { WM_err "WM_monitor_disable: invalid name '$name'"; return 1; }
    hyprctl eval "hl.monitor({ output = '$name', disabled = true })" >/dev/null
    return "$?"
}

# WM_monitor_dpms <name> on|off
WM_monitor_dpms() {
    local name="$1" state="$2" action
    [ -n "$name" ] || { WM_err "WM_monitor_dpms: missing name"; return 1; }
    WM_monitor_name_valid "$name" || { WM_err "WM_monitor_dpms: invalid name '$name'"; return 1; }
    case "$state" in
        on|true|1)   action=on ;;
        off|false|0) action=off ;;
        *) WM_err "WM_monitor_dpms: bad state '$state' (on|off)"; return 1 ;;
    esac
    hyprctl eval "hl.dispatch(hl.dsp.dpms({ action = '$action', monitor = '$name' }))" >/dev/null
}
