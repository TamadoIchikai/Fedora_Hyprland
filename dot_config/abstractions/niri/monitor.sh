#!/usr/bin/env bash
#
# niri/monitor.sh — niri output (monitor) operations.

# `niri msg --json outputs` returns an object keyed by connector name; emit a
# bare array with a normalized shape so callers behave like the other backends.
# niri keeps connected-but-disabled outputs in this list with `logical == null`,
# so the plain and `--all` listings are identical.
WM_monitor_list() {
    niri msg --json outputs 2>/dev/null | jq -c '
        [ to_entries[]
          | .value as $o
          | {
              name:     $o.name,
              active:   ($o.logical != null),
              enabled:  ($o.logical != null),
              disabled: ($o.logical == null)
            }
        ]'
}

# The focused output (`focused-output` is an Output or null).
WM_monitor_focused() {
    niri msg --json focused-output 2>/dev/null | jq -r '.name // empty'
}

WM_monitor_active_count() {
    niri msg --json outputs 2>/dev/null \
        | jq -r '[ to_entries[] | select(.value.logical != null) ] | length'
}

WM_monitor_present() {
    local name="$1"
    [ -n "$name" ] || { WM_err "WM_monitor_present: missing name"; return 1; }
    niri msg --json outputs 2>/dev/null \
        | jq -e --arg m "$name" 'has($m)' >/dev/null
}

# WM_monitor_enable <name> [mode] [pos] [scale] [mirror-of]
# mode/pos/scale are optional: omitted ones are left untouched.
# pos uses the `WxH` spelling (e.g. 1920x0); it is translated to niri's
# `position set <x> <y>`. niri has no native mirroring, so `mirror-of` is a
# no-op (warned), unlike the wlroots backends which stack the output.
#
# NOTE: `niri msg output ...` changes are runtime-only and are NOT written to
# the config; they are lost on the next config reload / session restart.
WM_monitor_enable() {
    local name="$1" mode="${2:-}" pos="${3:-}" scale="${4:-}" mirror="${5:-}"
    [ -n "$name" ] || { WM_err "WM_monitor_enable: missing name"; return 1; }
    WM_monitor_name_valid "$name" || { WM_err "WM_monitor_enable: invalid name '$name'"; return 1; }
    [ -z "$mode" ]   || WM_mode_valid "$mode"           || { WM_err "WM_monitor_enable: invalid mode '$mode'"; return 1; }
    [ -z "$pos" ]    || WM_mode_valid "$pos"            || { WM_err "WM_monitor_enable: invalid position '$pos'"; return 1; }
    [ -z "$scale" ]  || WM_number_valid "$scale"        || { WM_err "WM_monitor_enable: invalid scale '$scale'"; return 1; }
    [ -z "$mirror" ] || WM_monitor_name_valid "$mirror" || { WM_err "WM_monitor_enable: invalid mirror '$mirror'"; return 1; }
    WM_have niri || { WM_err "WM_monitor_enable: niri not found"; return 1; }

    [ -z "$mirror" ] || WM_err "WM_monitor_enable: niri has no native mirroring; ignoring mirror-of '$mirror'"

    # Turn the output on (no-op if already on).
    niri msg output "$name" on >/dev/null 2>&1

    # Pin the mode when one was given. Try the exact mode first, then retry
    # without the refresh (niri matches the refresh exactly while configs often
    # omit the fractional part, e.g. eDP-1 is 1920x1080@60.096 but configured
    # as @60).
    if [ -n "$mode" ]; then
        local rc=1
        niri msg output "$name" mode "$mode" >/dev/null 2>&1 && rc=0
        if [ "$rc" -ne 0 ] && [ "${mode%@*}" != "$mode" ]; then
            niri msg output "$name" mode "${mode%@*}" >/dev/null 2>&1 && rc=0
        fi
        [ "$rc" -eq 0 ] || return 1
    fi

    # niri wants `x y`; the API/scripts pass `WxH` (e.g. 1920x0).
    if [ -n "$pos" ]; then
        local x="${pos%x*}" y="${pos#*x}"
        niri msg output "$name" position set "$x" "$y" >/dev/null 2>&1 || return 1
    fi

    if [ -n "$scale" ]; then
        niri msg output "$name" scale "$scale" >/dev/null 2>&1 || return 1
    fi
    return 0
}

WM_monitor_disable() {
    local name="$1"
    [ -n "$name" ] || { WM_err "WM_monitor_disable: missing name"; return 1; }
    WM_monitor_name_valid "$name" || { WM_err "WM_monitor_disable: invalid name '$name'"; return 1; }
    WM_have niri || { WM_err "WM_monitor_disable: niri not found"; return 1; }
    niri msg output "$name" off >/dev/null 2>&1
}

# WM_monitor_dpms <name> on|off. niri's `output <name> on/off` is exactly the
# monitor power (DPMS) toggle.
WM_monitor_dpms() {
    local name="$1" state="$2"
    [ -n "$name" ] || { WM_err "WM_monitor_dpms: missing name"; return 1; }
    WM_monitor_name_valid "$name" || { WM_err "WM_monitor_dpms: invalid name '$name'"; return 1; }
    WM_have niri || { WM_err "WM_monitor_dpms: niri not found"; return 1; }
    case "$state" in
        on|true|1)   niri msg output "$name" on  >/dev/null ;;
        off|false|0) niri msg output "$name" off >/dev/null ;;
        *) WM_err "WM_monitor_dpms: bad state '$state' (on|off)"; return 1 ;;
    esac
}

# WM_monitor_watch: stream normalized monitor hotplug events, one per line:
#     add <name>     an output appeared
#     remove <name>  an output disappeared
#     change <name>  an output stayed but its active state changed
# niri's IPC has no output-hotplug event (OutputsChanged does not exist), so
# this polls `niri msg --json outputs` every $WM_NIRI_WATCH_INTERVAL seconds
# (default 2) and diffs successive snapshots. Blocks until interrupted; callers
# (e.g. the monitor watchdog) are responsible for reconnecting/stopping.
# TODO(niri): switch to `niri msg event-stream` once an outputs event exists.
WM_monitor_watch() {
    WM_have niri || { WM_err "WM_monitor_watch: niri not found"; return 1; }
    WM_have jq   || { WM_err "WM_monitor_watch: jq not found"; return 1; }

    local interval="${WM_NIRI_WATCH_INTERVAL:-2}" prev="" cur
    while :; do
        cur="$(niri msg --json outputs 2>/dev/null \
            | jq -r 'to_entries[]? | "\(.value.name)=\(.value.logical != null)"' 2>/dev/null \
            | sort | tr '\n' ' ')"
        if [ -n "$cur" ]; then
            if [ -z "$prev" ]; then
                prev="$cur"   # first snapshot = baseline
            else
                _niri_monitor_watch_diff "$prev" "$cur"
                prev="$cur"
            fi
        fi
        sleep "$interval"
    done
}

# Emit add/remove/change between two "name=active ..." snapshots. Private helper
# for WM_monitor_watch. Output names are compositor-controlled tokens (no IFS
# characters), so word-splitting the space-separated snapshots is safe here.
_niri_monitor_watch_diff() {
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
