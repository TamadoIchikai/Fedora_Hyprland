#!/usr/bin/env bash
#
# niri/window.sh — niri window operations.
#
# Window handles are niri numeric window ids.

# Emit a JSON object mapping workspace id -> output name, used to resolve a
# window's monitor (niri windows carry workspace_id, not output).
_niri_ws_output_map() {
    niri msg --json workspaces 2>/dev/null \
        | jq -c 'map({ key: (.id | tostring), value: (.output // null) }) | from_entries'
}

# Map an array of raw niri windows -> canonical (Hyprland-compatible) objects.
# Args: <workspace->output map JSON>; raw windows array on stdin.
_niri_map_windows() {
    local map="${1:-\{\}}"
    jq -c --argjson m "$map" '[ .[] | {
        address:   (.id | tostring),
        class:     (.app_id // ""),
        title:     (.title // ""),
        workspace: { id: (.workspace_id // 0) },
        monitor:   ($m[((.workspace_id // 0) | tostring)] // null),
        floating:  (.is_floating // false)
    }]'
}

# Map one raw niri window -> canonical object.
# Args: <window-json> <workspace->output map JSON>.
_niri_map_window() {
    local win="$1" map="${2:-\{\}}"
    printf '%s' "$win" | jq -c --argjson m "$map" '{
        address:   (.id | tostring),
        class:     (.app_id // ""),
        title:     (.title // ""),
        workspace: { id: (.workspace_id // 0) },
        monitor:   ($m[((.workspace_id // 0) | tostring)] // null),
        floating:  (.is_floating // false)
    }'
}

WM_window_list() {
    local class="" map
    while [ $# -gt 0 ]; do
        case "$1" in
            --class) class="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done

    map="$(_niri_ws_output_map)"
    if [ -n "$class" ]; then
        niri msg --json windows 2>/dev/null \
            | _niri_map_windows "$map" \
            | jq -c --arg c "$class" '[.[] | select(.class == $c)]'
    else
        niri msg --json windows 2>/dev/null | _niri_map_windows "$map"
    fi
}

WM_window_active() {
    local win map
    win="$(niri msg --json focused-window 2>/dev/null)"
    case "$win" in
        ''|null) printf '{}\n'; return 0 ;;
    esac
    map="$(_niri_ws_output_map)"
    _niri_map_window "$win" "$map"
}

WM_window_focus() {
    local handle="$1"
    [ -n "$handle" ] || { WM_err "WM_window_focus: missing handle"; return 1; }
    WM_window_handle_valid "$handle" || { WM_err "WM_window_focus: invalid handle '$handle'"; return 1; }
    niri msg action focus-window --id "$handle" >/dev/null
}

# WM_window_set_geometry <handle> <x> <y> [w] [h]
# Sets a window's absolute geometry (forces/uses floating). Used to restore a
# parked window's rule-defined position after a monitor layout change re-centers
# it. NOTE: niri's `move-floating-window --x/-y` parses a signed value as a
# *relative* adjustment (`+/-`), so only non-negative absolute coordinates are
# expressible via the CLI.
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
        niri msg action set-window-width  --id "$handle" "$w" >/dev/null
        niri msg action set-window-height --id "$handle" "$h" >/dev/null
    fi
    niri msg action move-floating-window --id "$handle" --x "$x" --y "$y" >/dev/null
}

WM_window_close() {
    local handle="$1"
    [ -n "$handle" ] || { WM_err "WM_window_close: missing handle"; return 1; }
    WM_window_handle_valid "$handle" || { WM_err "WM_window_close: invalid handle '$handle'"; return 1; }
    niri msg action close-window --id "$handle" >/dev/null
}

# WM_window_move_to_workspace <handle> <ws> [follow]
# <ws> is a workspace *reference*: a numeric index or a name (e.g. "park").
# follow=true focuses the destination; otherwise the window is moved silently.
WM_window_move_to_workspace() {
    local handle="$1" ws="$2" follow="${3:-false}" focus
    [ -n "$handle" ] || { WM_err "WM_window_move_to_workspace: missing handle"; return 1; }
    [ -n "$ws" ]     || { WM_err "WM_window_move_to_workspace: missing workspace"; return 1; }
    WM_window_handle_valid "$handle" || { WM_err "WM_window_move_to_workspace: invalid handle '$handle'"; return 1; }
    [[ "$ws" =~ ^[0-9]+$ || "$ws" =~ ^[A-Za-z0-9._-]+$ ]] \
        || { WM_err "WM_window_move_to_workspace: invalid workspace '$ws'"; return 1; }

    case "$follow" in true|1|yes) focus=true ;; *) focus=false ;; esac

    niri msg action move-window-to-workspace \
        --window-id "$handle" --focus "$focus" "$ws" >/dev/null
}

WM_window_workspace() {
    local handle="$1"
    WM_window_handle_valid "$handle" || { WM_err "WM_window_workspace: invalid handle '$handle'"; return 1; }
    niri msg --json windows 2>/dev/null \
        | jq -r --arg id "$handle" '.[] | select((.id | tostring) == $id) | (.workspace_id // 0)' \
        | head -n1
}

# WM_window_monitor <handle> -> the output name of the window's workspace.
WM_window_monitor() {
    local handle="$1" wsid
    WM_window_handle_valid "$handle" || { WM_err "WM_window_monitor: invalid handle '$handle'"; return 1; }
    wsid="$(WM_window_workspace "$handle")"
    [ -n "$wsid" ] || return 0
    niri msg --json workspaces 2>/dev/null \
        | jq -r --arg id "$wsid" '.[] | select((.id | tostring) == $id) | (.output // empty)' \
        | head -n1
}

WM_window_handle_valid() {
    case "${1:-}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}
