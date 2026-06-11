#!/usr/bin/env bash
set -euo pipefail

BG_LOG="${BG_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr-autostart.log}"

TIMER_FAST_TO_MEDIUM="${TIMER_FAST_TO_MEDIUM:-3}"
TIMER_FAST_TO_COMPLEX="${TIMER_FAST_TO_COMPLEX:-5}"
AUTO_CLOSE_AFTER="${AUTO_CLOSE_AFTER:-5}"

mkdir -p "$(dirname "$BG_LOG")"

clear

elapsed=0
medium_done=0
complex_done=0

log() {
    local msg
    printf -v msg '[%02ds] %s' "$elapsed" "$*"
    echo "$msg"
    echo "$msg" >>"$BG_LOG"
}

detach_run() {
    # Start command detached from this popup terminal.
    # This prevents apps from closing when the popup terminal exits.
    if command -v setsid >/dev/null 2>&1; then
        setsid -f "$@" >>"$BG_LOG" 2>&1 </dev/null || true
    else
        nohup "$@" >>"$BG_LOG" 2>&1 </dev/null &
    fi
}

run_once_name() {
    local procname="$1"
    shift

    if pgrep -u "$USER" -x "$procname" >/dev/null 2>&1; then
        log "skip: already running process: $procname"
        return 0
    fi

    log "start detached: $*"
    detach_run "$@"
}

run_once_pattern() {
    local pattern="$1"
    shift

    if pgrep -u "$USER" -f "$pattern" >/dev/null 2>&1; then
        log "skip: already running pattern: $pattern"
        return 0
    fi

    log "start detached: $*"
    detach_run "$@"
}

hypr_exec_ws() {
    local workspace="$1"
    shift

    local cmd="$*"

    log "start on workspace $workspace: $cmd"

    # Apps launched here are started by Hyprland, not by the popup shell.
    # So closing this popup terminal should not close them.
    hyprctl dispatch "hl.dsp.exec_cmd([[$cmd]], { workspace = [[$workspace silent]] })" \
        >>"$BG_LOG" 2>&1 || {
            log "warning: failed to start on workspace $workspace: $cmd"
            return 0
        }
}

start_user_service() {
    local service="$1"

    log "start service: $service"

    systemctl --user enable "$service" --now >>"$BG_LOG" 2>&1 || {
        log "warning: failed to start service: $service"
        return 0
    }
}

fast_startup() {
    log "========== fast_startup =========="

    run_once_name "waybar" waybar
    run_once_name "fcitx5" fcitx5 -d
    run_once_name "hyprsunset" hyprsunset
    run_once_pattern "wl-paste --watch cliphist store" wl-paste --watch cliphist store
    run_once_name "swaybg" swaybg -i "$HOME/.config/screenshots/background.png" -m fill
}

medium_startup() {
    log "========== medium_startup =========="


    hypr_exec_ws "11" "pavucontrol"
    hypr_exec_ws "11" "blueman-manager"
    hypr_exec_ws "11" "LocalSend.AppImage"
    hypr_exec_ws "11" "thunar"
    run_once_pattern "move-on-unfocus.sh" "$HOME/.config/waybar/scripts/move-on-unfocus.sh"
}

complex_startup() {
    log "========== complex_startup =========="

    run_once_name "keepassxc" keepassxc --minimized

    start_user_service "opentabletdriver.service"

    hypr_exec_ws "1" "Obsidian.AppImage"
    hypr_exec_ws "2" "vivaldi-stable"
    hypr_exec_ws "3" "mailspring --background --password-store=gnome-libsecret"
    hypr_exec_ws "10" "flatpak run io.github.mpc_qt.mpc-qt"
}

echo "Autostart popup"
echo "Real startup commands will be executed."
echo "Only this popup terminal will auto-close."
echo "Startup apps should stay open."
echo "Log file: $BG_LOG"
echo

fast_startup

while true; do
    sleep 1
    elapsed=$((elapsed + 1))
    log "elapsed: ${elapsed}s"

    if (( elapsed >= TIMER_FAST_TO_MEDIUM && medium_done == 0 )); then
        medium_startup
        medium_done=1
    fi

    if (( elapsed >= TIMER_FAST_TO_COMPLEX && complex_done == 0 )); then
        complex_startup
        complex_done=1
        break
    fi
done

echo
log "All startup groups finished."
log "Auto-closing popup terminal in ${AUTO_CLOSE_AFTER}s..."

for ((i = AUTO_CLOSE_AFTER; i >= 1; i--)); do
    sleep 1
    elapsed=$((elapsed + 1))
    log "closing popup in ${i}s"
done

exit 0
