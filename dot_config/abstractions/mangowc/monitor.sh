#!/usr/bin/env bash
#
# mangowc/monitor.sh — MangoWC monitor operations.
# NOTE: UNVERIFIED offline; every mapping is marked TODO(mango).

WM_monitor_list() {
    # TODO(mango): confirm whether `get all-monitors` includes disabled
    #              outputs, or whether wlr-randr is needed for those.
    mmsg get all-monitors
}

WM_monitor_focused() {
    # TODO(mango): verify verb (`get monitor`?) and field name.
    mmsg get monitor 2>/dev/null | jq -r '.name // empty'
}

WM_monitor_active_count() {
    mmsg get all-monitors | jq -r 'length'
}

WM_monitor_present() {
    local name="$1"
    [ -n "$name" ] || { WM_err "WM_monitor_present: missing name"; return 1; }
    mmsg get all-monitors | jq -e --arg m "$name" 'any(.[]; .name == $m)' >/dev/null
}

# WM_monitor_enable <name> [mode] [pos] [scale] [mirror-of]
# mode/pos/scale are optional: omitted ones are left untouched (used to
# force-enable an output without resetting its mode).
WM_monitor_enable() {
    local name="$1" mode="${2:-}" pos="${3:-}" scale="${4:-}" mirror="${5:-}" rc
    [ -n "$name" ] || { WM_err "WM_monitor_enable: missing name"; return 1; }

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
    # TODO(mango): verify `disable_monitor` arg form.
    mmsg dispatch disable_monitor "$name" >/dev/null
}

# WM_monitor_dpms <name> on|off  (mango: wakeup/sleep)
WM_monitor_dpms() {
    local name="$1" state="$2"
    [ -n "$name" ] || { WM_err "WM_monitor_dpms: missing name"; return 1; }
    case "$state" in
        on|true|1)   mmsg dispatch wakeup_monitor "$name" >/dev/null ;;
        off|false|0) mmsg dispatch sleep_monitor  "$name" >/dev/null ;;
        *) WM_err "WM_monitor_dpms: bad state '$state' (on|off)"; return 1 ;;
    esac
}
