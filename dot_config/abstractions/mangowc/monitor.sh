#!/usr/bin/env bash
#
# mangowc/monitor.sh — MangoWC monitor operations.

# `mmsg get all-monitors` returns {"monitors":[...]}; emit the bare array so
# callers behave identically to the Hyprland backend.
WM_monitor_list() {
    mmsg get all-monitors 2>/dev/null | jq -c '.monitors'
}

# Focused client's monitor, falling back to the monitor under the cursor.
WM_monitor_focused() {
    local m
    m="$(mmsg get all-clients 2>/dev/null | jq -r '.clients[] | select(.is_focused == true) | .monitor' | head -n1)"
    [ -n "$m" ] || m="$(mmsg get cursorpos 2>/dev/null | jq -r '.monitor // empty')"
    printf '%s' "$m"
}

WM_monitor_active_count() {
    mmsg get all-monitors 2>/dev/null | jq -r '[.monitors[] | select(.active == true)] | length'
}

WM_monitor_present() {
    local name="$1"
    [ -n "$name" ] || { WM_err "WM_monitor_present: missing name"; return 1; }
    WM_monitor_list 2>/dev/null | jq -e --arg m "$name" 'any(.[]; .name == $m)' >/dev/null
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

    # TODO(mango): verify enable_monitor args; mode/pos/scale may need
    #              wlr-randr instead of mmsg.
    mmsg dispatch enable_monitor "$name" >/dev/null
    rc=$?
    [ -n "$mode" ] && wlr-randr --output "$name" --mode "$mode" --pos "$pos" --scale "$scale" >/dev/null 2>&1 || true
    return "$rc"
}

WM_monitor_disable() {
    local name="$1"
    [ -n "$name" ] || { WM_err "WM_monitor_disable: missing name"; return 1; }
    WM_monitor_name_valid "$name" || { WM_err "WM_monitor_disable: invalid name '$name'"; return 1; }
    # TODO(mango): verify `disable_monitor` arg form.
    mmsg dispatch disable_monitor "$name" >/dev/null
}

# WM_monitor_dpms <name> on|off  (mango: wakeup/sleep)
WM_monitor_dpms() {
    local name="$1" state="$2"
    [ -n "$name" ] || { WM_err "WM_monitor_dpms: missing name"; return 1; }
    WM_monitor_name_valid "$name" || { WM_err "WM_monitor_dpms: invalid name '$name'"; return 1; }
    case "$state" in
        on|true|1)   mmsg dispatch wakeup_monitor "$name" >/dev/null ;;
        off|false|0) mmsg dispatch sleep_monitor  "$name" >/dev/null ;;
        *) WM_err "WM_monitor_dpms: bad state '$state' (on|off)"; return 1 ;;
    esac
}
