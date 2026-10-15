#!/usr/bin/env bash
#
# niri/exec.sh — niri command launching.
#
# NOTE: niri's `spawn`/`spawn-sh` actions have no per-spawn workspace option, so
#       WM_exec_on_workspace / WM_exec_on_park_workspace spawn the app and then
#       relocate its new window onto the target workspace (identifying the
#       window by the spawned pid), mirroring the MangoWC backend.
# SECURITY: the command passed to WM_exec* is treated as trusted — it is an
#       arbitrary command spawn, so it cannot be allowlisted. Callers must not
#       pass untrusted input.

WM_exec() {
    local cmd="$1"
    [ -n "$cmd" ] || { WM_err "WM_exec: missing command"; return 1; }

    # Prefer niri's IPC spawn once the session socket is available. At session
    # startup (config `spawn-at-startup`) NIRI_SOCKET may not yet be in the
    # environment, so fall back to a direct detached spawn.
    if [ -n "${NIRI_SOCKET:-}" ] && WM_have niri; then
        niri msg action spawn-sh -- "$cmd" >/dev/null 2>&1 && return 0
    fi

    setsid sh -c "$cmd" >/dev/null 2>&1 &
    disown 2>/dev/null || true
    return 0
}

# _niri_new_window_id <spid>
# Print the id of the window owned by <spid>: an exact pid match first, else a
# window sharing <spid>'s session (a forked child, e.g. `sh -c "a && b"`).
# Prints nothing until such a window exists.
_niri_new_window_id() {
    local spid="$1" id pid sid sid_hit=""
    while read -r id pid; do
        [ -n "$id" ] || continue
        if [ "$pid" = "$spid" ]; then printf '%s' "$id"; return 0; fi
        [ -n "$pid" ] || continue
        sid="$(awk '{print $6}' "/proc/$pid/stat" 2>/dev/null)"
        if [ -z "$sid_hit" ] && [ -n "$sid" ] && [ "$sid" = "$spid" ]; then
            sid_hit="$id"
        fi
    done < <(niri msg --json windows 2>/dev/null | jq -r '.[] | "\(.id) \(.pid // "")"' 2>/dev/null)
    if [ -n "$sid_hit" ]; then printf '%s' "$sid_hit"; fi
    return 0
}

# _niri_move_worker <ws> <focus true|false> <cmd>
# Spawn <cmd>, wait for its window (polling until the compositor IPC is ready —
# it can lag at session start — and the window maps), then move it onto the
# workspace reference <ws> (index or name). The move is held back by
# $WM_EXEC_TAG_DELAY (default 0.5s) so the window settles on screen before being
# relocated, which avoids the flash/tearing of relocating a surface mid-map.
# Diagnostics go to $WM_EXEC_TAG_LOG when set.
_niri_move_worker() {
    local ws="$1" focus="$2" cmd="$3"
    local log="${WM_EXEC_TAG_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/niri-exec-tag.log}" spid nid
    local delay="${WM_EXEC_TAG_DELAY:-0.5}"   # let the window settle before relocating
    setsid sh -c "$cmd" >/dev/null 2>&1 &
    spid=$!
    for _ in $(seq 1 300); do   # up to ~30s
        sleep 0.1
        nid="$(_niri_new_window_id "$spid")"
        if [ -n "$nid" ]; then
            sleep "$delay"
            if niri msg action move-window-to-workspace --window-id "$nid" --focus "$focus" "$ws" >/dev/null 2>&1; then
                [ -n "$log" ] && printf '%s ws=%s focus=%s window=%s pid=%s cmd=%q\n' \
                    "$(date -Is)" "$ws" "$focus" "$nid" "$spid" "$cmd" >>"$log" 2>/dev/null
            fi
            return 0
        fi
    done
    [ -n "$log" ] && printf '%s TIMEOUT ws=%s pid=%s cmd=%q\n' \
        "$(date -Is)" "$ws" "$spid" "$cmd" >>"$log" 2>/dev/null
    return 0
}

# _niri_exec_to_workspace <ws> <focus 0|1> <cmd>
_niri_exec_to_workspace() {
    local ws="$1" focus="$2" cmd="$3"
    [ -n "$ws" ] && [ -n "$cmd" ] || {
        WM_err "_niri_exec_to_workspace: usage: <ws> <focus> <cmd>"
        return 1
    }

    # Without IPC/jq the window cannot be relocated afterwards (niri has no
    # per-spawn workspace option) — fall back to a plain spawn.
    if [ -z "${NIRI_SOCKET:-}" ] || ! WM_have niri || ! WM_have jq; then
        WM_exec "$cmd"
        return 0
    fi

    local focus_flag=false
    [ "$focus" = "1" ] && focus_flag=true

    # Run the spawn+wait+move in a DETACHED session so it survives the caller:
    # autostart runs inside a popup terminal that is closed seconds in (SIGHUP
    # to its process group), which would kill a plain backgrounded waiter before
    # the window has mapped.
    setsid bash -c '
        source "$HOME/.config/abstractions/wm.sh" 2>/dev/null || true
        _niri_move_worker "$1" "$2" "$3"
    ' _ "$ws" "$focus_flag" "$cmd" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
    return 0
}

# WM_exec_on_workspace <ws> <cmd> [silent|nosilent]
WM_exec_on_workspace() {
    local ws="$1" cmd="$2" silent="${3:-silent}"
    [ -n "$ws" ] && [ -n "$cmd" ] || {
        WM_err "WM_exec_on_workspace: usage: <ws> <cmd> [silent|nosilent]"
        return 1
    }

    local focus_flag=0
    case "$silent" in nosilent|false|0|no) focus_flag=1 ;; esac
    _niri_exec_to_workspace "$ws" "$focus_flag" "$cmd"
}

# WM_exec_on_park_workspace <cmd>
# niri cannot target a workspace at spawn time. To reproduce Hyprland's
# `[workspace N silent]` autostart behaviour — open on the parking workspace
# without switching the view or stealing focus — spawn the app and then move its
# new window onto the parking workspace without focusing it.
WM_exec_on_park_workspace() {
    local cmd="$1"
    [ -n "$cmd" ] || { WM_err "WM_exec_on_park_workspace: missing command"; return 1; }

    local park
    park="$(WM_park_workspace 2>/dev/null)"
    [ -n "$park" ] || { WM_exec "$cmd"; return 0; }

    _niri_exec_to_workspace "$park" 0 "$cmd"
}

# WM_exec_floating <cmd> [center=true] [width=0.6] [height=0.6]
WM_exec_floating() {
    local cmd="$1" center="${2:-true}" w="${3:-0.6}" h="${4:-0.6}"
    [ -n "$cmd" ] || { WM_err "WM_exec_floating: missing command"; return 1; }
    WM_number_valid "$w" || { WM_err "WM_exec_floating: invalid width '$w'"; return 1; }
    WM_number_valid "$h" || { WM_err "WM_exec_floating: invalid height '$h'"; return 1; }

    # Best-effort: niri has no per-spawn float/center/size, so spawn, then make
    # the new window floating, size it (proportion), and center it — identifying
    # it by the spawned pid. Falls back to a plain spawn without IPC/jq.
    if [ -z "${NIRI_SOCKET:-}" ] || ! WM_have niri || ! WM_have jq; then
        WM_exec "$cmd"
        return 0
    fi

    local wpct hpct
    wpct="$(awk -v v="$w" 'BEGIN { printf "%d%%", (v * 100) + 0.5 }')"
    hpct="$(awk -v v="$h" 'BEGIN { printf "%d%%", (v * 100) + 0.5 }')"

    setsid bash -c '
        source "$HOME/.config/abstractions/wm.sh" 2>/dev/null || true
        cmd="$1"; wpct="$2"; hpct="$3"; center="$4"
        setsid sh -c "$cmd" >/dev/null 2>&1 &
        spid=$!
        for _ in $(seq 1 300); do   # up to ~30s
            sleep 0.1
            nid="$(_niri_new_window_id "$spid")"
            [ -n "$nid" ] || continue
            sleep 0.2
            niri msg action move-window-to-floating --id "$nid" >/dev/null 2>&1
            niri msg action set-window-width  --id "$nid" "$wpct" >/dev/null 2>&1
            niri msg action set-window-height --id "$nid" "$hpct" >/dev/null 2>&1
            case "$center" in true|1|yes) niri msg action center-window --id "$nid" >/dev/null 2>&1 ;; esac
            break
        done
    ' _ "$cmd" "$wpct" "$hpct" "$center" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
    return 0
}
