#!/usr/bin/env bash
#
# mangowc/exec.sh — MangoWC command launching.
# NOTE: MangoWC has no native per-spawn workspace/float options, so the
#       workspace/floating variants are best-effort and marked TODO(mango).
# SECURITY: the command passed to WM_exec* is treated as trusted — it is an
#       arbitrary command spawn, so it cannot be allowlisted. Callers must not
#       pass untrusted input. `mmsg` comma/arg parsing is TODO(mango).

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

# WM_exec_on_workspace <ws> <cmd> [silent|nosilent]
WM_exec_on_workspace() {
    local ws="$1" cmd="$2" silent="${3:-silent}"
    [ -n "$ws" ] && [ -n "$cmd" ] || {
        WM_err "WM_exec_on_workspace: usage: <ws> <cmd> [silent|nosilent]"
        return 1
    }

    # TODO(mango): `spawn_on_empty` only targets an EMPTY tag. For non-empty
    #   tags (e.g. the parking tag) the window must be relocated afterward by
    #   detecting the new client and running `tag,<ws> client,<id>`. Phase-3.
    WM_exec "$cmd"
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

    # Without IPC (or jq) the window cannot be relocated afterwards, so fall
    # back to a plain spawn (mango has no per-spawn tag option).
    if [ -z "$park" ] || [ -z "${MANGO_INSTANCE_SIGNATURE:-}" ] || \
       ! WM_have mmsg || ! WM_have jq; then
        WM_exec "$cmd"
        return 0
    fi

    local before
    before="$(mmsg get all-clients 2>/dev/null | jq -c '(.clients // []) | map(.id)' 2>/dev/null)"
    [ -n "$before" ] || before='[]'

    WM_exec "$cmd" || return 0

    # Wait for the new client id to appear, then move it onto the park tag
    # silently. Backgrounded so autostart's sequential dispatches aren't delayed.
    (
        local nid
        for _ in $(seq 1 50); do   # up to ~5s
            sleep 0.1
            nid="$(mmsg get all-clients 2>/dev/null |
                jq -r --argjson b "$before" '(((.clients // []) | map(.id)) - $b)[0] // empty' 2>/dev/null)"
            if [ -n "$nid" ]; then
                mmsg dispatch "tagsilent,$park client,$nid" >/dev/null 2>&1
                break
            fi
        done
    ) &
    disown 2>/dev/null || true
    return 0
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
