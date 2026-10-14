#!/usr/bin/env bash
#
# hyprland/window.sh — Hyprland window operations.
# Window handles are Hyprland addresses (hex, optionally 0x-prefixed).

WM_window_list() {
    local class=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --class) class="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [ -n "$class" ]; then
        hyprctl clients -j | jq -c --arg c "$class" '[.[] | select(.class == $c)]'
    else
        hyprctl clients -j
    fi
}

WM_window_active() {
    local out
    out="$(hyprctl activewindow -j 2>/dev/null)"
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
    else
        printf '{}\n'
    fi
}

WM_window_focus() {
    local handle="$1"
    [ -n "$handle" ] || { WM_err "WM_window_focus: missing handle"; return 1; }
    hyprctl dispatch "hl.dsp.focus({ window = 'address:$handle' })" >/dev/null
}

WM_window_close() {
    local handle="$1"
    [ -n "$handle" ] || { WM_err "WM_window_close: missing handle"; return 1; }
    hyprctl dispatch "hl.dsp.window.close({ window = 'address:$handle' })" >/dev/null
}

WM_window_move_to_workspace() {
    local handle="$1" ws="$2" follow="${3:-false}" wslua
    [ -n "$handle" ] || { WM_err "WM_window_move_to_workspace: missing handle"; return 1; }
    [ -n "$ws" ]     || { WM_err "WM_window_move_to_workspace: missing workspace"; return 1; }

    case "$ws" in
        *[!0-9]*) wslua="$(WM_lua_str "$ws")" ;;
        *)        wslua="$ws" ;;
    esac
    case "$follow" in true|1|yes) follow=true ;; *) follow=false ;; esac

    hyprctl dispatch "hl.dsp.window.move({ workspace = $wslua, window = 'address:$handle', follow = $follow })" >/dev/null
}

WM_window_workspace() {
    local handle="$1"
    hyprctl clients -j | jq -r --arg a "$handle" '.[] | select(.address == $a) | .workspace.id' | head -n1
}

WM_window_handle_valid() {
    case "${1:-}" in
        ''|*[!0-9a-fA-Fx]*) return 1 ;;
    esac
    [[ "${1}" =~ ^(0x)?[0-9a-fA-F]+$ ]]
}
