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
        class:     (.app_id // .class // ""),
        title:     (.title // ""),
        workspace: { id: ((.tags // [])[0] // 0) },
        monitor:   (.monitor // null),
        floating:  (.is_floating // false)
    }'
}

# Map an array of raw mango clients -> canonical array.
WM_mango_map_clients() {
    jq -c '[.[] | {
        address:   (.id | tostring),
        class:     (.app_id // .class // ""),
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

    # TODO(mango): verify `get all-clients` output shape.
    if [ -n "$class" ]; then
        mmsg get all-clients | WM_mango_map_clients | jq -c --arg c "$class" '[.[] | select(.class == $c)]'
    else
        mmsg get all-clients | WM_mango_map_clients
    fi
}

WM_window_active() {
    # TODO(mango): verify `get focusing-client` output shape.
    local out
    out="$(mmsg get focusing-client 2>/dev/null)"
    if [ -n "$out" ] && [ "$out" != "null" ]; then
        printf '%s\n' "$out" | WM_mango_map_client
    else
        printf '{}\n'
    fi
}

WM_window_focus() {
    local handle="$1"
    [ -n "$handle" ] || { WM_err "WM_window_focus: missing handle"; return 1; }
    # TODO(mango): verify `focusid client,<id>`.
    mmsg dispatch focusid "client,$handle" >/dev/null
}

WM_window_close() {
    local handle="$1"
    [ -n "$handle" ] || { WM_err "WM_window_close: missing handle"; return 1; }
    # TODO(mango): verify `killclient` accepts a client target.
    mmsg dispatch killclient "client,$handle" >/dev/null
}

WM_window_move_to_workspace() {
    local handle="$1" ws="$2" follow="${3:-false}"
    [ -n "$handle" ] || { WM_err "WM_window_move_to_workspace: missing handle"; return 1; }
    [ -n "$ws" ]     || { WM_err "WM_window_move_to_workspace: missing workspace"; return 1; }

    # `tag,<mask> client,<id>` moves; `tagsilent` is the same without focus.
    # TODO(mango): verify follow semantics (whether `tag` already switches the
    #              view, and whether the extra `view` below is needed/correct).
    case "$follow" in
        true|1|yes)
            mmsg dispatch "tag,$ws" "client,$handle" >/dev/null
            mmsg dispatch "view,$ws" >/dev/null
            ;;
        *)
            mmsg dispatch "tagsilent,$ws" "client,$handle" >/dev/null
            ;;
    esac
}

WM_window_workspace() {
    local handle="$1"
    # TODO(mango): verify `.tags`; a window may occupy multiple tags, this
    #              returns the first.
    mmsg get all-clients \
        | jq -r --arg id "$handle" '.[] | select((.id | tostring) == $id) | ((.tags // [])[0] // 0)' \
        | head -n1
}

WM_window_handle_valid() {
    case "${1:-}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}
