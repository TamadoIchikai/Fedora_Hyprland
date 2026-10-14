#!/usr/bin/env bash
#
# mangowc/window.sh — MangoWC window operations.
#
# Window handles are MangoWC numeric client ids.
# NOTE: The mmsg JSON schemas below are UNVERIFIED offline (no live MangoWC
#       session available). Each mapping is marked TODO(mango) for phase-3.

# Map one raw mango client -> Hyprland-compatible canonical object.
WM_mango_map_client() {
    jq -c '{
        address:   (.id | tostring),
        class:     (.appid // .app_id // .class // ""),
        title:     (.title // ""),
        workspace: { id: ((.tags // [])[0] // 0) },
        monitor:   (.monitor // null),
        floating:  (.is_floating // false)
    }'
}

# Map an array of raw mango clients -> canonical array. Accepts either
# {"clients":[...]} (as returned by `mmsg get all-clients`) or a bare array.
WM_mango_map_clients() {
    jq -c '[ (.clients // .)[] | {
        address:   (.id | tostring),
        class:     (.appid // .app_id // .class // ""),
        title:     (.title // ""),
        workspace: { id: ((.tags // [])[0] // 0) },
        monitor:   (.monitor // null),
        floating:  (.is_floating // false)
    }]'
}

WM_window_list() {
    local class=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --class) class="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [ -n "$class" ]; then
        mmsg get all-clients | WM_mango_map_clients | jq -c --arg c "$class" '[.[] | select(.class == $c)]'
    else
        mmsg get all-clients | WM_mango_map_clients
    fi
}

WM_window_active() {
    # The focused client, if any (`all-clients` -> is_focused).
    mmsg get all-clients 2>/dev/null \
        | jq -c '[ (.clients // .)[] | select(.is_focused == true) ][0] // {}' \
        | WM_mango_map_client
}

WM_window_focus() {
    local handle="$1"
    [ -n "$handle" ] || { WM_err "WM_window_focus: missing handle"; return 1; }
    WM_window_handle_valid "$handle" || { WM_err "WM_window_focus: invalid handle '$handle'"; return 1; }
    # TODO(mango): verify `focusid client,<id>`.
    mmsg dispatch focusid "client,$handle" >/dev/null
}

# WM_window_set_geometry <handle> <x> <y> [w] [h]
# Sets a window's absolute geometry. Mango's `movewin`/`resizewin` treat bare
# integers as absolute values (no +/- sign) and force the window floating (see
# move_window/resize_window in dispatch/bind.c). Used to restore a parked
# window's rule-defined position after a monitor layout change re-centers it.
WM_window_set_geometry() {
    local handle="$1" x="$2" y="$3" w="${4:-}" h="${5:-}"
    [ -n "$handle" ] || { WM_err "WM_window_set_geometry: missing handle"; return 1; }
    [ -n "$x" ] && [ -n "$y" ] || { WM_err "WM_window_set_geometry: missing position"; return 1; }
    WM_window_handle_valid "$handle" || { WM_err "WM_window_set_geometry: invalid handle '$handle'"; return 1; }
    local v
    for v in "$x" "$y" "$w" "$h"; do
        [ -z "$v" ] || [[ "$v" =~ ^-?[0-9]+$ ]] || {
            WM_err "WM_window_set_geometry: non-integer value '$v'"; return 1; }
    done

    if [ -n "$w" ] && [ -n "$h" ]; then
        mmsg dispatch "resizewin,$w,$h" "client,$handle" >/dev/null
    fi
    mmsg dispatch "movewin,$x,$y" "client,$handle" >/dev/null
}

WM_window_close() {
    local handle="$1"
    [ -n "$handle" ] || { WM_err "WM_window_close: missing handle"; return 1; }
    WM_window_handle_valid "$handle" || { WM_err "WM_window_close: invalid handle '$handle'"; return 1; }
    # TODO(mango): verify `killclient` accepts a client target.
    mmsg dispatch killclient "client,$handle" >/dev/null
}

# MangoWC tags are per-monitor, so a plain `tag,<ws>` re-tags a client on its
# *own* monitor and cannot bring a window over from the other screen.
#   - same monitor: `tag,<ws> client` re-tags + switches the view + focuses.
#   - other monitor: `tagsilent,<ws> client` sets the tag, then
#     `tagmon,<monitor>,1 client` moves it to the focused monitor
#     (tag_monitor keeps the client's tags) and focuses it.
#     (`tagcrossmon` is not usable here: when the target monitor is the focused
#      one it short-circuits to tag_client, which stays on the client's own
#      monitor.)
# follow=false -> tag <ws> on the window's own monitor, without focus (park).
WM_window_move_to_workspace() {
    local handle="$1" ws="$2" follow="${3:-false}" mon my_mon
    [ -n "$handle" ] || { WM_err "WM_window_move_to_workspace: missing handle"; return 1; }
    [ -n "$ws" ]     || { WM_err "WM_window_move_to_workspace: missing workspace"; return 1; }
    WM_window_handle_valid "$handle" || { WM_err "WM_window_move_to_workspace: invalid handle '$handle'"; return 1; }
    [[ "$ws" =~ ^[0-9]+$ ]] || { WM_err "WM_window_move_to_workspace: invalid workspace '$ws'"; return 1; }

    case "$follow" in
        true|1|yes)
            mon="$(WM_monitor_focused 2>/dev/null)"
            [ -n "$mon" ] || mon="$(WM_window_monitor "$handle" 2>/dev/null)"
            WM_monitor_name_valid "$mon" || {
                WM_err "WM_window_move_to_workspace: could not resolve monitor for '$handle'"
                return 1
            }
            my_mon="$(WM_window_monitor "$handle" 2>/dev/null)"
            if [ "$mon" = "$my_mon" ]; then
                mmsg dispatch "tag,$ws" "client,$handle" >/dev/null
            else
                mmsg dispatch "tagsilent,$ws" "client,$handle" >/dev/null
                mmsg dispatch "tagmon,$mon,1" "client,$handle" >/dev/null
            fi
            ;;
        *)
            mmsg dispatch "tagsilent,$ws" "client,$handle" >/dev/null
            ;;
    esac
}

WM_window_workspace() {
    local handle="$1"
    WM_window_handle_valid "$handle" || { WM_err "WM_window_workspace: invalid handle '$handle'"; return 1; }
    # A window may occupy multiple tags; return the first.
    mmsg get all-clients 2>/dev/null \
        | jq -r --arg id "$handle" '(.clients // .)[] | select((.id | tostring) == $id) | ((.tags // [])[0] // 0)' \
        | head -n1
}

# WM_window_monitor <handle> -> the client's monitor name (mango tags are
# per-monitor, so callers must pair a tag with its monitor).
WM_window_monitor() {
    local handle="$1"
    WM_window_handle_valid "$handle" || { WM_err "WM_window_monitor: invalid handle '$handle'"; return 1; }
    mmsg get all-clients 2>/dev/null \
        | jq -r --arg h "$handle" '(.clients // .)[] | select((.id | tostring) == $h) | .monitor // empty' \
        | head -n1
}

WM_window_handle_valid() {
    case "${1:-}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}
