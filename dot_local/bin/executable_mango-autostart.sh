#!/usr/bin/env bash
#
# mango-autostart.sh — entry point for mango's config `exec_once`.
#
# Mango runs `exec_once` (via `sh -c`) before it enters its Wayland event loop
# and, on some builds, before IPC is fully usable. This script logs the boot
# environment, then launches the shared startup wrapper; if the wrapper fails to
# produce the popup terminal it falls back to a direct detached spawn so
# startup never silently dies.

LOG="${XDG_CACHE_HOME:-$HOME/.cache}/mango-autostart-debug.log"
POPUP_TITLE="AutostartTestPopup"
RUNNER="$HOME/.local/bin/autostart.sh"

{
    echo "=== $(date -Is) mango-autostart.sh start ==="
    echo "HOME=$HOME"
    echo "WM_CURR(before)=${WM_CURR:-<unset>}"
    echo "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-<unset>}"
    echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<unset>}"
    echo "MANGO_INSTANCE_SIGNATURE=${MANGO_INSTANCE_SIGNATURE:-<unset>}"
    echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>}"
    echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-<unset>}"
    echo "TERM=${TERM:-<unset>}"
    echo "PATH=$PATH"
    echo "foot=$(command -v foot || echo MISSING)"
    echo "wrapper=$(command -v "$HOME/.local/bin/autostart-wrapper.sh" || echo MISSING)"
} >>"$LOG" 2>&1

# exec_once runs just before wl_display_run(); give the seat/output time to settle.
sleep 2

# ----- Boot-time display selection -----
# If an external monitor is physically connected at boot, switch to the
# configured dual-monitor mode (default "external") before the desktop apps
# load, so the session comes up on the right display. Mirrors the
# hyprland.start hook in ~/.config/hypr/hyprland.lua. Detection is
# compositor-agnostic: WM_monitor_list --all lists every connected output,
# enabled or not, without needing the compositor IPC to be ready yet.
DISPLAY_SCRIPT="$HOME/.local/bin/fuzzel-DisplayMode.sh"
DUAL_MONITOR_MODE="${DUAL_MONITOR_MODE:-external}"
EXTERNAL_OUTPUT="${EXTERNAL_OUTPUT:-HDMI-A-1}"

source "$HOME/.config/abstractions/wm.sh" 2>/dev/null || true

if [ -x "$DISPLAY_SCRIPT" ] && command -v jq >/dev/null 2>&1; then
    external_connected="$(WM_monitor_list --all 2>/dev/null \
        | jq -r --arg e "$EXTERNAL_OUTPUT" '.[] | select(.name == $e) | .name' 2>/dev/null | head -n1)"
    if [ -n "$external_connected" ]; then
        echo "[$(date -Is)] external '$external_connected' connected; applying mode '$DUAL_MONITOR_MODE'" >>"$LOG" 2>&1
        "$DISPLAY_SCRIPT" --mode "$DUAL_MONITOR_MODE" >>"$LOG" 2>&1
        # Give the DRM subsystem a moment to light up the pixels before loading apps.
        sleep 1
    else
        echo "[$(date -Is)] no external monitor; staying on laptop screen" >>"$LOG" 2>&1
    fi
fi

"$HOME/.local/bin/autostart-wrapper.sh" >>"$LOG" 2>&1
rc=$?
echo "[$(date -Is)] mango-autostart: wrapper rc=$rc" >>"$LOG" 2>&1

sleep 3
if ! pgrep -f "$POPUP_TITLE" >/dev/null 2>&1; then
    echo "[$(date -Is)] no popup after wrapper; direct-spawn fallback" >>"$LOG" 2>&1
    setsid env \
        BG_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-autostart.log" \
        TIMER_FAST_TO_MEDIUM=3 TIMER_FAST_TO_COMPLEX=6 AUTO_CLOSE_AFTER=5 \
        foot --title "$POPUP_TITLE" bash "$RUNNER" >>"$LOG" 2>&1 &
    disown
fi
