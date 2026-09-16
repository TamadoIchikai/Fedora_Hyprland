#!/usr/bin/env bash
set -uo pipefail
set +m
umask 077

# ---------------------------------------------------------------
# Hyprland Monitor Hotplug Watchdog (event-driven, zero polling)
#
# Three independent event sources:
#   1. udev DRM connector events (kernel level, reliable)
#   2. Hyprland socket2 IPC events (monitorremoved/added)
#   3. logind PrepareForSleep(false) = resume from suspend/hibernate,
#      guarantees a display check on every wake even if the hotplug
#      events above are late or missing.
#
# What this handles:
#   - The "blind state": 0 real monitors rendering (Hyprland hides
#     this behind a virtual "FALLBACK" output that shows up as an
#     active monitor, so we count only REAL hardware monitors).
#     Rescue: reload config, then force-enable the laptop output.
#   - The "ghost display" state: a physically connected external is
#     silently disabled (signal present, no picture). On a
#     monitoradded event we re-enable it + turn DPMS on.
# ---------------------------------------------------------------

# ----- Configuration (env vars may override) -----
LAPTOP="${LAPTOP_OUTPUT:-eDP-1}"
EXTERNAL="${EXTERNAL_OUTPUT:-HDMI-A-1}"
COOLDOWN="${COOLDOWN:-5}"                 # min seconds between rescues
SETTLE_DELAY="${SETTLE_DELAY:-1}"         # settle time after an event
RECONNECT_DELAY=2                          # reconnect a dead event source
RESCUE_TRIES="${RESCUE_TRIES:-3}"          # force-enable attempts
LAST_SKIP_LOG=0                                      # for rate-limiting lock-skip logs

# ----- Private runtime directory -----
# Locks and the cooldown stamp live in a user-only directory (default
# /run/user/<uid>, mode 0700) instead of /tmp. /tmp is world-writable:
# a hostile pre-created symlink at one of these predictable names would be
# followed by our O_TRUNC opens (exec 8>, echo >), silently truncating an
# arbitrary file we can write, and could be used to hold the instance lock
# as a denial-of-service.
RUNTIME_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/hyprland-monitor-watcher"
mkdir -m 700 -p "$RUNTIME_DIR" 2>/dev/null || {
    echo "Error: cannot create runtime dir: $RUNTIME_DIR" >&2
    exit 1
}
LOCKFILE="$RUNTIME_DIR/watcher.lock"                # mutex for checks/rescues
INSTANCE_LOCK="$RUNTIME_DIR/watcher.instance"       # single-instance guard
STAMP="$RUNTIME_DIR/rescue.cooldown"                # cooldown marker

# jq predicate selecting real (hardware) outputs: Hyprland's virtual
# FALLBACK output and headless outputs are not real monitors.
REAL_MONITOR='((.name | startswith("FALLBACK") | not) and (.name | startswith("HEADLESS-") | not))'

# ----- Environment sanity checks -----
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    echo "Error: HYPRLAND_INSTANCE_SIGNATURE is not set. Are you running this inside Hyprland?" >&2
    exit 1
fi

SOCKET="${XDG_RUNTIME_DIR:-/tmp}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
if [[ ! -S "$SOCKET" ]]; then
    SOCKET="/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
fi
if [[ ! -S "$SOCKET" ]]; then
    echo "Error: Hyprland event socket not found: $SOCKET" >&2
    exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required" >&2; exit 1; }
command -v socat >/dev/null 2>&1 || { echo "Error: socat is required" >&2; exit 1; }
command -v flock >/dev/null 2>&1 || { echo "Error: flock is required" >&2; exit 1; }

# ----- Single-instance guard -----
# Held for the lifetime of this process. A second copy of the script
# (e.g. a manual ./run while the systemd service is active) exits
# immediately instead of fighting over the mutex below.
exec 8>"$INSTANCE_LOCK"
flock -n 8 || {
    echo "Error: another watcher instance is already running. Exiting." >&2
    exit 0
}

NOTIFY=0
command -v notify-send >/dev/null 2>&1 && NOTIFY=1

# ----- Helpers -----
log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

notify_event() {
    local msg="$1"
    local urgency="${2:-normal}"
    if (( NOTIFY == 1 )); then
        notify-send -u "$urgency" -t 4000 "Auto Rescue" "$msg" >/dev/null 2>&1 &
    fi
}

# Count actively rendering REAL hardware monitors (FALLBACK / HEADLESS-* excluded).
real_monitor_count() {
    local count
    count=$(hyprctl monitors -j 2>/dev/null \
        | jq -r "[.[] | select($REAL_MONITOR)] | length" 2>/dev/null)
    if [[ "$count" =~ ^[0-9]+$ ]]; then
        printf '%s' "$count"
    else
        printf ''
    fi
}

# True if output is currently an active (rendering) monitor.
output_active() {
    local mon="$1"
    hyprctl monitors -j 2>/dev/null \
        | jq -e --arg m "$mon" 'any(.[]; .name == $m)' >/dev/null 2>&1
}

# True if output is known to Hyprland (active OR inactive/disabled).
output_present() {
    local mon="$1"
    hyprctl monitors all -j 2>/dev/null \
        | jq -e --arg m "$mon" 'any(.[]; .name == $m)' >/dev/null 2>&1
}

# Connector names are compositor-controlled tokens (letters, digits,
# '-', '.', '_'). A name that fails this check is never interpolated into
# a hyprctl eval Lua string, so a malformed or hostile name cannot inject
# Lua (e.g. a ' that breaks out of the string literal).
valid_mon_name() {
    [[ "$1" =~ ^[A-Za-z0-9._-]{1,64}$ ]]
}

# Some GPUs resume with outputs active but DPMS off (black screen).
# Re-light anything Hyprland currently renders.
ensure_active_dpms() {
    hyprctl monitors all -j 2>/dev/null \
        | jq -r ".[] | select($REAL_MONITOR and .disabled == false) | .name" 2>/dev/null \
        | while read -r m; do
            hyprctl dispatch dpms on "$m" >/dev/null 2>&1
        done
}

# ----- Blind-state rescue (serialized via flock) -----
rescue_laptop() {
    exec 9>"$LOCKFILE"
    flock -n 9 || {
        # A burst of events spawns several rescues at once; while one holds
        # the mutex the rest just skip. Rate-limit the noise but keep the
        # message so genuine lock contention is still visible.
        local now
        now=$(date +%s)
        if (( now - LAST_SKIP_LOG >= 2 )); then
            log "rescue already in progress, skipping"
            LAST_SKIP_LOG="$now"
        fi
        exec 9>&-
        return 0
    }

    sleep "$SETTLE_DELAY"

    local count
    count=$(real_monitor_count)
    if [[ -z "$count" ]]; then
        log "warning: could not read monitor count; skipping rescue"
        exec 9>&-
        return 1
    fi

    # A real monitor is rendering -> healthy. Do NOT stamp the cooldown:
    # if this check ran early (before Hyprland finished removing the
    # output), the follow-up event must be allowed to trigger again.
    if (( count > 0 )); then
        log "ok: $count real monitor(s) rendering, no rescue needed"
        exec 9>&-
        return 0
    fi

    # Blind state confirmed. Enforce a minimum gap between rescues.
    local now last
    now=$(date +%s)
    last=$(cat "$STAMP" 2>/dev/null); last=${last:-0}
    if (( now - last < COOLDOWN )); then
        log "blind state, but rescue cooldown active; skipping"
        exec 9>&-
        return 0
    fi
    echo "$now" > "$STAMP"

    log "BLIND STATE: 0 real monitors rendering (FALLBACK/headless only). Rescuing..."
    notify_event "Display lost. Re-enabling $LAPTOP..."

    # Stage 1: reload config, re-applying monitor rules.
    hyprctl reload >/dev/null 2>&1
    sleep 1

    if output_active "$LAPTOP"; then
        log "rescue ok (config reload): $LAPTOP is back on"
        notify_event "Laptop screen restored (config reload)"
        exec 9>&-
        return 0
    fi

    # Stage 2: force-enable the laptop output directly, with verification.
    if ! valid_mon_name "$LAPTOP"; then
        log "ERROR: LAPTOP output name is not a safe token; refusing eval: $LAPTOP"
        notify_event "RESCUE FAILED - LAPTOP output name is unsafe" critical
        exec 9>&-
        return 1
    fi
    local attempt
    for (( attempt = 1; attempt <= RESCUE_TRIES; attempt++ )); do
        log "force-enabling $LAPTOP (attempt $attempt/$RESCUE_TRIES)"
        hyprctl eval "hl.monitor({ output = '$LAPTOP', disabled = false })" >/dev/null 2>&1
        hyprctl dispatch dpms on "$LAPTOP" >/dev/null 2>&1
        sleep 1.5
        if output_active "$LAPTOP"; then
            log "rescue ok (forced enable): $LAPTOP is back on"
            notify_event "Laptop screen restored (forced enable)"
            exec 9>&-
            return 0
        fi
    done

    log "ERROR: $LAPTOP still not active after $RESCUE_TRIES attempts. Manual intervention required."
    notify_event "RESCUE FAILED - no display is active" critical

    exec 9>&-
    return 1
}

# ----- Repair a monitor that was just (re)added but is not rendering -----
# Fixes the "ghost display" case: signal present (LED lit) but no
# picture, because Hyprland re-added the output in a disabled state.
repair_added() {
    local mon="$1"

    case "$mon" in
        FALLBACK*|HEADLESS-*|"") return 0 ;;
    esac
    valid_mon_name "$mon" || {
        log "ignoring monitoradded event with unsafe name: $mon"
        return 0
    }

    exec 9>"$LOCKFILE"
    flock -n 9 || return 0

    sleep "$SETTLE_DELAY"

    if output_active "$mon"; then
        # Rendering already; just make sure DPMS is not stuck off.
        hyprctl dispatch dpms on "$mon" >/dev/null 2>&1
        log "monitor $mon added and rendering (dpms ensured)"
    elif output_present "$mon"; then
        log "monitor $mon present but not rendering; re-enabling"
        hyprctl eval "hl.monitor({ output = '$mon', disabled = false })" >/dev/null 2>&1
        hyprctl dispatch dpms on "$mon" >/dev/null 2>&1
        sleep 1
        if output_active "$mon"; then
            log "repair ok: $mon is rendering again"
            notify_event "$mon restored"
        else
            log "repair failed: $mon still not rendering"
        fi
    else
        log "monitor $mon added event, but not present in Hyprland"
    fi

    exec 9>&-
}

maybe_rescue() {
    rescue_laptop &
}

# Extract the monitor name from monitoradded/removed and their v2 forms.
event_monitor_name() {
    local line="$1"
    local payload
    case "$line" in
        monitoraddedv2\>\>*|monitorremovedv2\>\>*)
            payload="${line#*>>}"
            printf '%s' "${payload#*,}" | cut -d, -f1
            ;;
        monitoradded\>\>*|monitorremoved\>\>*)
            printf '%s' "${line#*>>}"
            ;;
    esac
}

# ----- Event source 1: udev DRM connector events (kernel level) -----
listen_udev() {
    while true; do
        log "udev DRM listener starting..."
        udevadm monitor --udev --subsystem-match=drm/drm_connector 2>/dev/null \
            | while read -r line; do
                case "$line" in
                    *card*) maybe_rescue ;;
                esac
            done
        log "udev DRM listener exited; reconnecting in ${RECONNECT_DELAY}s"
        sleep "$RECONNECT_DELAY"
    done
}

# ----- Event source 2: Hyprland socket2 IPC events -----
listen_hypr() {
    while true; do
        if [[ ! -S "$SOCKET" ]]; then
            log "hyprland socket missing; retrying in ${RECONNECT_DELAY}s"
            sleep "$RECONNECT_DELAY"
            continue
        fi
        log "hyprland socket listener starting: $SOCKET"
        socat -U - UNIX-CONNECT:"$SOCKET" 2>/dev/null \
            | while read -r line; do
                case "$line" in
                    monitorremovedv2*|monitoraddedv2*)
                        # v2 events carry an ID,NAME,DESC payload; the legacy
                        # "monitorremoved>>NAME" twin always accompanies them
                        # (Hyprland >= 0.55), so we react to v2 only and avoid
                        # doubling every reaction and log line. React to
                        # FALLBACK/HEADLESS churn too, but don't echo it.
                        name="$(event_monitor_name "$line")"
                        case "$name" in
                            FALLBACK*|HEADLESS-*)
                                maybe_rescue
                                ;;
                            *)
                                log "hyprland event: $line"
                                maybe_rescue
                                if [[ "$line" == monitoraddedv2* ]]; then
                                    repair_added "$name" &
                                fi
                                ;;
                        esac
                        ;;
                esac
            done
        log "hyprland socket listener exited; reconnecting in ${RECONNECT_DELAY}s"
        sleep "$RECONNECT_DELAY"
    done
}

# ----- Event source 3: system suspend/resume (logind) -----
# After suspend/hibernate, udev and Hyprland are usually late (or
# silent) about connectors that changed while frozen, so a blind state
# can linger with no event to react to. logind's PrepareForSleep(false)
# fires on EVERY wake, guaranteeing we re-check the display state
# regardless of which hotplug events the kernel/compositor sent.
listen_resume() {
    while true; do
        log "resume listener starting..."
        dbus-monitor --system "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" 2>/dev/null \
            | while read -r line; do
                case "$line" in
                    *boolean\ false*)
                        log "system resume detected; running display check"
                        # Give the kernel + compositor time to finish waking.
                        sleep 2
                        maybe_rescue
                        ensure_active_dpms
                        ;;
                esac
            done
        log "resume listener exited; reconnecting in ${RECONNECT_DELAY}s"
        sleep "$RECONNECT_DELAY"
    done
}

# ----- Main -----
log "starting hyprland monitor watchdog (laptop=$LAPTOP, external=$EXTERNAL)"

listen_udev &
UDEV_PID=$!
listen_hypr &
HYPR_PID=$!
listen_resume &
RESUME_PID=$!

# ----- Graceful shutdown -----
# Take down the whole tree (listener subshells, socat, udevadm, the
# `while read` pipeline halves, any in-flight rescue/repair) so nothing
# survives after we exit. The instance lock (fd 8) and the check mutex
# release automatically once the last process holding them dies.
STOP=0

# Kill a parent before its descendants: a killed parent cannot respawn a
# fresh pipeline during teardown (the bug that used to orphan listeners).
kill_children() {
    local pid="$1"
    local children child
    children=$(pgrep -P "$pid" 2>/dev/null)
    for child in $children; do
        kill "$child" 2>/dev/null
        kill_children "$child"
    done
}

shutdown_gracefully() {
    local sig="$1"
    [[ "$STOP" -eq 1 ]] && exit 0
    STOP=1
    trap - INT EXIT     # keep TERM armed: the group signal hits us too
    local pgid
    pgid=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ')
    log "received $sig; shutting down gracefully"
    if [[ -n "$pgid" ]] && (( pgid == $$ )); then
        # We lead the process group: terminate everyone at once so no
        # listener can respawn a pipeline mid-teardown.
        kill -- "-$$" 2>/dev/null
    else
        # Fallback for unusual invocations: recursive PID kill only.
        kill_children "$$"
    fi
    wait 2>/dev/null
    exit 0
}

trap 'shutdown_gracefully TERM' TERM
trap 'shutdown_gracefully INT' INT
trap 'kill_children "$$" 2>/dev/null' EXIT

wait "$UDEV_PID" "$HYPR_PID" "$RESUME_PID"