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
    mmsg dispatch "spawn,$cmd" >/dev/null
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
    mmsg dispatch "spawn,$cmd" >/dev/null
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
    mmsg dispatch "spawn,$cmd" >/dev/null
}
