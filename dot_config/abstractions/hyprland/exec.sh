#!/usr/bin/env bash
#
# hyprland/exec.sh — Hyprland command launching.

WM_exec() {
    local cmd="$1"
    [ -n "$cmd" ] || { WM_err "WM_exec: missing command"; return 1; }
    hyprctl dispatch "hl.dsp.exec_cmd($(WM_lua_long "$cmd"))" >/dev/null
}

# WM_exec_on_workspace <ws> <cmd> [silent|nosilent]
# Defaults to launching silently (no view switch), matching existing usage.
WM_exec_on_workspace() {
    local ws="$1" cmd="$2" silent="${3:-silent}" spec
    [ -n "$ws" ] && [ -n "$cmd" ] || {
        WM_err "WM_exec_on_workspace: usage: <ws> <cmd> [silent|nosilent]"
        return 1
    }

    spec="$ws"
    case "$silent" in
        ''|silent|true|1|yes) spec="$ws silent" ;;
    esac

    hyprctl dispatch "hl.dsp.exec_cmd($(WM_lua_long "$cmd"), { workspace = $(WM_lua_long "$spec") })" >/dev/null
}

# WM_exec_floating <cmd> [center=true] [width=0.6] [height=0.6]
WM_exec_floating() {
    local cmd="$1" center="${2:-true}" w="${3:-0.6}" h="${4:-0.6}"
    [ -n "$cmd" ] || { WM_err "WM_exec_floating: missing command"; return 1; }
    case "$center" in true|1|yes) center=true ;; *) center=false ;; esac

    hyprctl dispatch "hl.dsp.exec_cmd($(WM_lua_long "$cmd"), { float = true, center = $center, size = { '(monitor_w*$w)', '(monitor_h*$h)' } })" >/dev/null
}
