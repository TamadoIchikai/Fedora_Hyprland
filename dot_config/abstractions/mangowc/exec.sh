#!/usr/bin/env bash
#
# mangowc/exec.sh — MangoWC command launching.
# NOTE: MangoWC has no native per-spawn workspace option, so WM_exec_on_workspace
#       and WM_exec_on_park_workspace spawn the app and then relocate its new
#       window onto the target tag (identifying the window by the spawned pid).
# SECURITY: the command passed to WM_exec* is treated as trusted — it is an
#       arbitrary command spawn, so it cannot be allowlisted. Callers must not
#       pass untrusted input.

WM_exec() {
    local cmd="$1"
    [ -n "$cmd" ] || { WM_err "WM_exec: missing command"; return 1; }

    # Prefer mango's IPC spawn when the session socket is available. At session
    # startup (config `exec`/`exec_once`) mango initialises IPC *after* running
    # those commands, so MANGO_INSTANCE_SIGNATURE is not yet in the environment
    # and `mmsg` cannot connect. Fall back to a direct detached spawn so login
    # autostart still works.
    if [ -n "${MANGO_INSTANCE_SIGNATURE:-}" ] && WM_have mmsg; then
        mmsg dispatch "spawn,$cmd" >/dev/null 2>&1 && return 0
    fi

    setsid sh -c "$cmd" >/dev/null 2>&1 &
    disown 2>/dev/null || true
    return 0
}

# _mango_new_client_id <spid>
# Print the id of the client owned by <spid>: an exact pid match first, else a
# client sharing <spid>'s session (a forked child, e.g. `sh -c "a && b"`).
# Prints nothing until such a client exists.
_mango_new_client_id() {
    local spid="$1" id pid sid sid_hit=""
    while read -r id pid; do
        [ -n "$id" ] || continue
        if [ "$pid" = "$spid" ]; then printf '%s' "$id"; return 0; fi
        sid="$(awk '{print $6}' "/proc/$pid/stat" 2>/dev/null)"
        if [ -z "$sid_hit" ] && [ -n "$sid" ] && [ "$sid" = "$spid" ]; then
            sid_hit="$id"
        fi
    done < <(mmsg get all-clients 2>/dev/null | jq -r '(.clients // [])[]|"\(.id) \(.pid)"' 2>/dev/null)
    if [ -n "$sid_hit" ]; then printf '%s' "$sid_hit"; fi
    return 0
}

# _mango_tag_worker <tag> <dispatch> <cmd>
# Spawn <cmd>, wait for its window (polling until the compositor IPC is ready —
# it can lag at session start — and the client maps), then move it onto <tag>
# with the given dispatch verb. The move is held back by $WM_EXEC_TAG_DELAY
# (default 0.5s) so the window settles on screen before being relocated, which
# avoids the flash/tearing of relocating a surface mid-map. Diagnostics go to
# $WM_EXEC_TAG_LOG when set.
_mango_tag_worker() {
    local tag="$1" dispatch="$2" cmd="$3"
    local log="${WM_EXEC_TAG_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/mango-exec-tag.log}" spid nid
    local delay="${WM_EXEC_TAG_DELAY:-0.5}"   # let the window settle before relocating
    setsid sh -c "$cmd" >/dev/null 2>&1 &
    spid=$!
    for _ in $(seq 1 300); do   # up to ~30s
        sleep 0.1
        nid="$(_mango_new_client_id "$spid")"
        if [ -n "$nid" ]; then
            sleep "$delay"
            if mmsg dispatch "$dispatch,$tag client,$nid" >/dev/null 2>&1; then
                [ -n "$log" ] && printf '%s tag=%s %s client=%s pid=%s cmd=%q\n' \
                    "$(date -Is)" "$tag" "$dispatch" "$nid" "$spid" "$cmd" >>"$log" 2>/dev/null
            fi
            return 0
        fi
    done
    [ -n "$log" ] && printf '%s TIMEOUT tag=%s pid=%s cmd=%q\n' \
        "$(date -Is)" "$tag" "$spid" "$cmd" >>"$log" 2>/dev/null
    return 0
}

# _mango_exec_to_tag <tag> <silent 0|1> <cmd>
_mango_exec_to_tag() {
    local tag="$1" silent="$2" cmd="$3"
    [ -n "$tag" ] && [ -n "$cmd" ] || {
        WM_err "_mango_exec_to_tag: usage: <tag> <silent> <cmd>"
        return 1
    }

    # Without IPC/jq the window cannot be relocated afterwards (mango has no
    # per-spawn tag option) — fall back to a plain spawn.
    if [ -z "${MANGO_INSTANCE_SIGNATURE:-}" ] || ! WM_have mmsg || ! WM_have jq; then
        WM_exec "$cmd"
        return 0
    fi

    local dispatch="tagsilent"
    [ "$silent" = "0" ] && dispatch="tag"

    # Run the spawn+wait+tag in a DETACHED session so it survives the caller:
    # autostart runs inside a popup terminal that is closed seconds in (SIGHUP
    # to its process group), which would kill a plain backgrounded waiter before
    # the window has mapped.
    setsid bash -c '
        source "$HOME/.config/abstractions/wm.sh" 2>/dev/null || true
        _mango_tag_worker "$1" "$2" "$3"
    ' _ "$tag" "$dispatch" "$cmd" </dev/null >/dev/null 2>&1 &
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

    local silent_flag=1
    case "$silent" in nosilent|false|0|no) silent_flag=0 ;; esac
    _mango_exec_to_tag "$ws" "$silent_flag" "$cmd"
}

# WM_exec_on_park_workspace <cmd>
# MangoWC cannot target a tag at spawn time. To reproduce Hyprland's
# `[workspace N silent]` autostart behaviour — open on the parking tag without
# switching the view or stealing focus — spawn the app and then move its new
# window onto the parking tag with `tagsilent` (move-without-view-switch).
# The window is only relocated, never focused.
WM_exec_on_park_workspace() {
    local cmd="$1"
    [ -n "$cmd" ] || { WM_err "WM_exec_on_park_workspace: missing command"; return 1; }

    local park
    park="$(WM_park_workspace 2>/dev/null)"
    [ -n "$park" ] || { WM_exec "$cmd"; return 0; }

    _mango_exec_to_tag "$park" 1 "$cmd"
}

# WM_exec_floating <cmd> [center=true] [width=0.6] [height=0.6]
WM_exec_floating() {
    local cmd="$1" center="${2:-true}" w="${3:-0.6}" h="${4:-0.6}"
    [ -n "$cmd" ] || { WM_err "WM_exec_floating: missing command"; return 1; }
    WM_number_valid "$w" || { WM_err "WM_exec_floating: invalid width '$w'"; return 1; }
    WM_number_valid "$h" || { WM_err "WM_exec_floating: invalid height '$h'"; return 1; }

    # TODO(mango): no per-spawn float/center/size. Spawn, then apply
    #   `togglefloating` + `centerwin` + `resizewin client,<id>` to the new
    #   client (identify it by class/title). Phase-3.
    WM_exec "$cmd"
}
