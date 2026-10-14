#!/usr/bin/env bash
#
# mangowc/monitor.sh — MangoWC monitor operations.

# `mmsg get all-monitors` returns {"monitors":[...]}; emit the bare array so
# callers behave identically to the Hyprland backend.
#
# With --all, list every *physically connected* output (including ones that are
# currently disabled) via wlr-randr, so layout pickers can still detect a screen
# that is turned off. mmsg only reports enabled monitors.
WM_monitor_list() {
    case "${1:-}" in
    --all|-a)
        WM_have wlr-randr && wlr-randr --json 2>/dev/null |
            jq -c '[.[] | {name: .name, active: .enabled, enabled: .enabled, disabled: (.enabled | not)}]' 2>/dev/null ||
            printf '[]'
        ;;
    *)
        mmsg get all-monitors 2>/dev/null | jq -c '.monitors'
        ;;
    esac
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
# mode/pos/scale are optional: omitted ones are left untouched.
# pos uses the `WxH` spelling (e.g. 1920x0); it is translated to wlr-randr's
# `x,y` form. MangoWC/wlroots has no native mirroring, so `mirror-of` is a
# best-effort fallback that stacks this output on top of the source output.
WM_monitor_enable() {
    local name="$1" mode="${2:-}" pos="${3:-}" scale="${4:-}" mirror="${5:-}"
    local pos_final mpos
    [ -n "$name" ] || { WM_err "WM_monitor_enable: missing name"; return 1; }
    WM_monitor_name_valid "$name" || { WM_err "WM_monitor_enable: invalid name '$name'"; return 1; }
    [ -z "$mode" ]   || WM_mode_valid "$mode"           || { WM_err "WM_monitor_enable: invalid mode '$mode'"; return 1; }
    [ -z "$pos" ]    || WM_mode_valid "$pos"            || { WM_err "WM_monitor_enable: invalid position '$pos'"; return 1; }
    [ -z "$scale" ]  || WM_number_valid "$scale"        || { WM_err "WM_monitor_enable: invalid scale '$scale'"; return 1; }
    [ -z "$mirror" ] || WM_monitor_name_valid "$mirror" || { WM_err "WM_monitor_enable: invalid mirror '$mirror'"; return 1; }
    WM_have wlr-randr || { WM_err "WM_monitor_enable: wlr-randr not found"; return 1; }

    # wlr-randr wants `x,y`; the API/scripts pass `WxH` (e.g. 1920x0).
    pos_final="${pos/x/,}"

    # No native mirroring: stack this output on top of the source output.
    if [ -n "$mirror" ]; then
        mpos="$(wlr-randr --json 2>/dev/null |
            jq -r --arg m "$mirror" '.[] | select(.name == $m) | "\(.position.x),\(.position.y)"' 2>/dev/null |
            head -n1)"
        [ -n "$mpos" ] && [ "$mpos" != "null,null" ] && pos_final="$mpos"
    fi

    local -a common=(--output "$name" --on)
    [ -n "$pos_final" ] && common+=(--pos "$pos_final")
    [ -n "$scale" ]     && common+=(--scale "$scale")

    # Enable the output (pinning the mode when one was given). Try the exact
    # mode first, then fall back to the refresh-less form (wlr-randr matches
    # the refresh exactly while configs often omit the fractional part, e.g.
    # eDP-1 is 1920x1080@60.096 but configured as @60).
    local rc
    if [ -n "$mode" ]; then
        rc=1
        wlr-randr "${common[@]}" --mode "$mode" >/dev/null 2>&1 && rc=0
        if [ "$rc" -ne 0 ] && [ "${mode%@*}" != "$mode" ]; then
            wlr-randr "${common[@]}" --mode "${mode%@*}" >/dev/null 2>&1 && rc=0
        fi
    else
        wlr-randr "${common[@]}" >/dev/null 2>&1
        rc=$?
    fi
    [ "$rc" -eq 0 ] || return 1

    # Mango resets a disabled monitor's cached geometry to {0,0}, so when the
    # output is re-enabled at exactly 0,0 the compositor's "position changed?"
    # guard (monitor.c:1234) is false, wlr_output_layout_add() is skipped, and
    # the layout pass then auto-places it to the right of the others (add_auto)
    # -> e.g. the laptop lands at 3840 instead of 0. Re-assert the requested
    # position once so it lands where we asked. Skipped for the mirror fallback
    # (which deliberately stacks on another output).
    if [ -n "$pos_final" ] && [ -z "$mirror" ]; then
        sleep 0.2
        local actual
        actual="$(wlr-randr --json 2>/dev/null |
            jq -r --arg m "$name" '.[] | select(.name == $m) |
                "\(.position.x),\(.position.y)"' 2>/dev/null | head -n1)"
        if [ -n "$actual" ] && [ "$actual" != "$pos_final" ]; then
            wlr-randr --output "$name" --pos "$pos_final" >/dev/null 2>&1
        fi
    fi
    return 0
}

WM_monitor_disable() {
    local name="$1"
    [ -n "$name" ] || { WM_err "WM_monitor_disable: missing name"; return 1; }
    WM_monitor_name_valid "$name" || { WM_err "WM_monitor_disable: invalid name '$name'"; return 1; }
    WM_have wlr-randr || { WM_err "WM_monitor_disable: wlr-randr not found"; return 1; }
    wlr-randr --output "$name" --off >/dev/null 2>&1
}

# WM_monitor_dpms <name> on|off  (mango: wakeup/sleep).
# mmsg joins its argv with spaces and the dispatch parser splits on commas, so
# the monitor name must be part of the same comma-separated token.
WM_monitor_dpms() {
    local name="$1" state="$2"
    [ -n "$name" ] || { WM_err "WM_monitor_dpms: missing name"; return 1; }
    WM_monitor_name_valid "$name" || { WM_err "WM_monitor_dpms: invalid name '$name'"; return 1; }
    case "$state" in
        on|true|1)   mmsg dispatch "wakeup_monitor,$name" >/dev/null ;;
        off|false|0) mmsg dispatch "sleep_monitor,$name"  >/dev/null ;;
        *) WM_err "WM_monitor_dpms: bad state '$state' (on|off)"; return 1 ;;
    esac
}

# WM_monitor_watch: stream normalized monitor hotplug events, one per line:
#     add <name>     an output appeared
#     remove <name>  an output disappeared
#     change <name>  an output stayed but its active state changed
# `mmsg watch all-monitors` re-emits the full monitor list on every change, so
# successive snapshots are diffed. Blocks until the stream closes; callers
# (e.g. the monitor watchdog) are responsible for reconnecting.
WM_monitor_watch() {
    WM_have mmsg || { WM_err "WM_monitor_watch: mmsg not found"; return 1; }
    WM_have jq   || { WM_err "WM_monitor_watch: jq not found"; return 1; }

    local line prev="" cur
    mmsg watch all-monitors 2>/dev/null | while IFS= read -r line; do
        cur="$(jq -r '.monitors[]? | "\(.name)=\(.active)"' <<<"$line" 2>/dev/null | sort | tr '\n' ' ')"
        [ -n "$cur" ] || continue
        [ -n "$prev" ] || { prev="$cur"; continue; }   # first snapshot = baseline
        _mango_monitor_watch_diff "$prev" "$cur"
        prev="$cur"
    done
}

# Emit add/remove/change between two "name=active ..." snapshots. Private helper
# for WM_monitor_watch. Output names are compositor-controlled tokens (no IFS
# characters), so word-splitting the space-separated snapshots is safe here.
_mango_monitor_watch_diff() {
    local prev="$1" cur="$2" tok name otok pact
    for tok in $cur; do
        name="${tok%%=*}"
        pact=""
        for otok in $prev; do
            [ "${otok%%=*}" = "$name" ] && { pact="${otok#*=}"; break; }
        done
        if   [ -z "$pact" ];             then printf 'add %s\n'    "$name"
        elif [ "$pact" != "${tok#*=}" ]; then printf 'change %s\n' "$name"
        fi
    done
    for tok in $prev; do
        name="${tok%%=*}"
        pact=""
        for otok in $cur; do
            [ "${otok%%=*}" = "$name" ] && { pact=1; break; }
        done
        [ -n "$pact" ] || printf 'remove %s\n' "$name"
    done
}
