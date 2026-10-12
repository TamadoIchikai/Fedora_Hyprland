#!/usr/bin/env bash
set -euo pipefail

# file_manager.sh (super+E)
#
# Keeps MAX warm dolphins parked (tiled) on workspace 11. Each press pulls
# exactly ONE parked dolphin (most recently used) onto the current workspace
# as a tiled, focused window, and exits immediately. A background keeper then
# tops 11 back up to MAX, so rapid presses stack quickly to the usual 1-2
# dolphins without ever waiting on a cold launch. 11 never holds more than
# MAX. If a press finds the garage empty, it just fires the keeper to repay
# the debt (refill 11 to MAX) and exits without pulling anything.
#
# 11 is a parking garage: dolphins parked there stay tiled and never more than
# MAX are parked. New dolphins are spawned directly onto 11 via a per-spawn
# rule on hl.dsp.exec_cmd (workplace + silent), so they never flash on the
# current workspace and dialogs from the running instance are unaffected (the
# rule is scoped to the spawned PID, not a global rule). The keeper's poll+park
# below is a fallback in case a window ever maps elsewhere. The main flock only
# serializes the instant bring; the keeper runs on its own lock so spawning
# never blocks a press.

# Locks live in the per-user runtime dir (0700), not shared /tmp where another
# local user could pre-create the file and starve the flock. Fallback to /tmp
# with a restrictive umask if XDG_RUNTIME_DIR is unset.
umask 077
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/file_manager.lock"
exec 9>"$LOCK_FILE"
flock -w 15 9 || exit 1

CLASS="org.kde.dolphin"
DUMP_WS="11"
MAX="2"

command -v hyprctl >/dev/null || exit 1
command -v jq >/dev/null || exit 1

valid_addr() { [[ "$1" =~ ^0x[0-9a-fA-F]+$ ]]; }
valid_ws()   { [[ "$1" =~ ^[0-9]+$ ]]; }
dispatch()   { hyprctl dispatch "$1" >/dev/null || true; }

launch_dolphin() {
    dispatch "hl.dsp.exec_cmd([[dolphin --new-window]], { workspace = [[$DUMP_WS silent]] })"
}

bring_to() { # addr workspace - move there + focus it
    valid_addr "$1" || return 1
    valid_ws "$2"   || return 1
    dispatch "hl.dsp.window.move({ window = \"address:$1\", workspace = $2, follow = true })"
}

park_at() { # addr workspace - move there silently
    valid_addr "$1" || return 1
    valid_ws "$2"   || return 1
    dispatch "hl.dsp.window.move({ window = \"address:$1\", workspace = $2, follow = false })"
}

focus_win()  { valid_addr "$1" && dispatch "hl.dsp.focus({ window = \"address:$1\" })"; }
real_close() { valid_addr "$1" && dispatch "hl.dsp.window.close({ window = \"address:$1\" })"; }

on_ws() { # ws - print every dolphin address there, most recent first (reads stdin JSON)
    jq -r --arg c "$CLASS" --arg w "$1" '
        [ .[]
            | select(.class == $c and .mapped == true)
            | select(.address != null and .address != "")
            | select(.workspace != null and (.workspace.id | tostring) == $w)
            | {addr: .address, f: (.focusHistoryID // 0)}
        ] | sort_by(-.f) | .[]
        | .addr
    ' 2>/dev/null || true
}

spawned_on() { # known-addrs JSON - first mapped dolphin not in the known set (reads stdin JSON)
    jq -r --argjson k "$1" --arg c "$CLASS" '
        [ .[]
            | select(.class == $c and .mapped == true)
            | select(.address != null and .address != "")
            | select(.workspace != null and .workspace.id != null)
            | .address as $a
            | select(($k | index($a)) == null)
            | $a
        ][0] // empty
    ' 2>/dev/null || true
}

sweep() { # workspace 11 keeps at most MAX dolphins - really close any extras
    local cur
    cur="$(hyprctl clients -j 2>/dev/null || true)"
    [[ -n "$cur" ]] || return 0
    readarray -t on11 < <(on_ws "$DUMP_WS" <<<"$cur")
    for (( i = MAX; i < ${#on11[@]}; i++ )); do
        real_close "${on11[$i]}"
    done
}

keep_warm() { # background keeper - top 11 back up to MAX
    exec 9>&-                     # drop the main lock so presses are never pinned
    exec 8>"${LOCK_FILE}.worker"
    flock -w 3 8 || return 1

    local cur need known found
    cur="$(hyprctl clients -j 2>/dev/null || true)"
    [[ -n "$cur" ]] || return 0

    need=$(( MAX - $(on_ws "$DUMP_WS" <<<"$cur" | wc -l) ))
    if (( need > 0 )); then
        known="$(jq -c --arg c "$CLASS" '
            [ .[]
                | select(.class == $c and .mapped == true)
                | select(.address != null and .address != "")
                | .address
            ]
        ' <<<"$cur" 2>/dev/null || printf '[]')"

        for _ in $(seq 1 "$need"); do
            launch_dolphin
        done

        # Let the window actually map before scanning: polling earlier just
        # burns a ~10ms hyprctl+jq round trip on the same empty state. The
        # map time is dolphin's, not ours.
        sleep 0.2
        for _ in $(seq 1 40); do
            cur="$(hyprctl clients -j 2>/dev/null || true)"
            [[ -n "$cur" ]] || break
            found="$(spawned_on "$known" <<<"$cur")"
            if [[ -n "$found" ]]; then
                park_at "$found" "$DUMP_WS"
                known="$(jq -c --arg a "$found" '. + [$a]' <<<"$known" 2>/dev/null || printf '[]')"
            fi
            (( $(on_ws "$DUMP_WS" <<<"$cur" | wc -l) >= MAX )) && break
            sleep 0.05
        done
    fi
    sweep
}

clients="$(hyprctl clients -j 2>/dev/null || true)"
[[ -n "$clients" ]] || exit 1

current_ws="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)"
valid_ws "$current_ws" || exit 1

# Most recent dolphin parked on 11: focus it when already here, otherwise pull
# it here. Either way the keeper tops 11 back to MAX in the background, so rapid
# presses stack to the usual 1-2 dolphins without waiting on a cold start.
readarray -t parked < <(on_ws "$DUMP_WS" <<<"$clients")
if (( ${#parked[@]} > 0 )); then
    if [[ "$current_ws" == "$DUMP_WS" ]]; then
        focus_win "${parked[0]}"
    else
        bring_to "${parked[0]}" "$current_ws"
    fi
fi
keep_warm &