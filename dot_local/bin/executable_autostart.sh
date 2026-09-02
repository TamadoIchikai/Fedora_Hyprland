#!/usr/bin/env bash
set -euo pipefail

BG_LOG="${BG_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/autostart.log}"
AUDIO_OS_START="${HOME}/.local/share/sounds/OS_Startup.mp3"
AUDIO_PLAYER="paplay --volume=65536"
TIMER_FAST_TO_MEDIUM="${TIMER_FAST_TO_MEDIUM:-3}"
TIMER_FAST_TO_COMPLEX="${TIMER_FAST_TO_COMPLEX:-5}"
AUTO_CLOSE_AFTER="${AUTO_CLOSE_AFTER:-5}"

# --- START ARTWORK PADDING ---
START_ART_PADDING_TOP=4
START_ART_PADDING_BOTTOM=0

# --- END ARTWORK PADDING ---
END_ART_PADDING_TOP=0
END_ART_PADDING_BOTTOM=0

mkdir -p "$(dirname "$BG_LOG")"

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

    # Workspace is embedded into a Hyprland Lua expression. Only accept a
    # plain number (or a "N silent" pair) so hostile input can't break out of
    # the [[ ]] string literal and inject dispatch commands.
    if ! [[ "$workspace" =~ ^[0-9]+(\ silent)?$ ]]; then
        log "warning: refusing unsafe workspace value: $workspace"
        return 0
    fi

    # The command is also embedded in a [[ ]] Lua string; reject the closing
    # delimiter so neither field can inject extra Hyprland expressions.
    if [[ "$cmd" == *"]]"* ]]; then
        log "warning: refusing command containing ]] : $cmd"
        return 0
    fi

    log "start on workspace $workspace: $cmd"

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
    run_once_pattern "wl-paste --type text" wl-paste --type text --watch cliphist store
    run_once_pattern "wl-paste --type image" wl-paste --type image --watch cliphist store
    run_once_name "cliphist wipe" cliphist wipe
    run_once_name "swaybg" swaybg -i "${HOME}/.config/screenshots/background.png" -m fill
    run_once_pattern "polkit-mate" /usr/libexec/polkit-mate-authentication-agent-1
}

medium_startup() {
    log "========== medium_startup =========="

    hypr_exec_ws "11" "pavucontrol"
    hypr_exec_ws "11" "blueman-manager"
    hypr_exec_ws "11" "LocalSend.AppImage"
    hypr_exec_ws "11" "thunar"
    run_once_name "move-on-unfocus.sh" "$HOME/.config/waybar/scripts/move-on-unfocus.sh"
    run_once_name "deviceMonitor.sh" "$HOME/.local/bin/deviceMonitor.sh"
}

complex_startup() {
    log "========== complex_startup =========="

    # 1. Start all other applications immediately (Unblocked)
    start_user_service "opentabletdriver.service"

    run_once_pattern "md.obsidian.Obsidian" flatpak run md.obsidian.Obsidian
    hypr_exec_ws "2" "zen"
    run_once_pattern "betterbird" flatpak run eu.betterbird.Betterbird -mail

    local tray_attempts=0
    log "checking for active waybar instance before launching keepassxc..."
    while ! pgrep -u "$USER" -x "waybar" >/dev/null 2>&1; do
        if (( tray_attempts >= 10 )); then
            log "warning: waybar check timed out, attempting to start keepassxc anyway"
            break
        fi
        sleep 0.5
        ((tray_attempts++))
    done

    # Buffer window to let waybar's tray module bind to DBus completely
    sleep 0.5
    run_once_name "keepassxc" keepassxc --minimized
}

print_centered() {
    local art="$1"
    local term_cols=$(tput cols 2>/dev/null || echo 80)

    local max_width=0
    local art_lines=0

    while IFS= read -r line; do
        (( ${#line} > max_width )) && max_width=${#line}
        (( ++art_lines ))
    done <<< "$art"

    local h_pad=$(( (term_cols - max_width) / 2 ))
    (( h_pad < 0 )) && h_pad=0

    local spaces=$(printf '%*s' "$h_pad" "")
    while IFS= read -r line; do
        echo "${spaces}${line}"
    done <<< "$art"
}

# Store the ASCII art and text into a SINGLE variable
ASCII_ART_START=$(cat << "EOF"
 ⠀⠀⠀            ⠀⠀⠀⠀⠀⠀⢀⠤⠐⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀     ⠀⠀  ⠀⠀⠀⠀⢀⠞⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⢀⠑⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀       ⠀⠀ ⠀⠀⠀⢠⠏⠀⡄⡀⠁⠀⠤⠂⠀⠀⠀⠀⢐⠀⠀⠀⠁⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀        ⠀⠀⢰⠟⢳⣾⠂⠈⠀⠒⠂⠀⠀⠐⠄⠀⠀⠀⢀⠓⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⠤⠶⣿⢶⢶⣾⣦⢄⡄⠀⠠⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀        ⠀⠀⠀⠂⢤⣿⡟⠇⠀⠀⢀⣇⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡴⠉⠤⠤⢣⠻⡾⡬⠷⠀⣹⠮⢧⡾⣗⡆⠈⠉⢳⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀
 ⢀        ⠀⠀⣰⢦⣤⣾⣿⣤⠼⠥⢽⡿⡡⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀⣸⢸⠿⣏⣇⣀⡘⣓⣀⣰⣝⣠⣙⠤⣠⢼⣇⡨⣆⣀⣀⣀⢀⡀⢀⠀
⠀        ⠀⠀⠀⠈⡁⣏⠉⠽⠓⣮⣞⣿⠃⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠰⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠉⠍⢰⢞⡏⠉⠉⠉⠉⣽⠓⠋⠉⠉⠲⣭⡋⠉⠙⠀⠘⠛⠀⠀⠀⠀⠀
⠀        ⠀⠀⠀⠀⠀⠀⠀⠀⠁⢏⡈⠻⡿⢙⠀⡃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣴⠀⠀⠀⠀⠀⠀⠀⢀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⢩⢺⢢⠁⠀⠀⡘⠀⠀⠀⡔⠒⠂⢘⣷⠶⡌⠀⠀⠀⠀⠀⠀⠀⠀
⠀        ⠀⠀⠀⠀⠀⠀⣖⢳⣀⠀⠰⣿⡿⠂⠀⠏⠀⠀⠨⢨⡀⠀⠀⠀⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⣠⣿⣆⠀⠀⠀⠀⠀⠀⠀⠈⣿⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⠃⠀⠀⠀⢁⠀⠀⠀⢣⣀⣀⣤⣗⣇⠀⡄⠀⠀⠀⢄⠀⠀⠀
⠀        ⠀⠀⠀⠀⠠⡾⠋⠉⢹⠻⢶⣿⠲⠀⠀⠀⠀⠀⠀⠀⠐⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⠴⢒⣨⣥⣶⣿⣿⣿⣷⣤⣄⡀⠀⢀⣠⡾⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⢯⣨⣿⢖⡁⢰⡆⠀⡘⠀⠀⠀
⠀        ⠀⠀⠀⠀⡌⠀⠸⠇⢈⠵⣿⡋⣳⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣤⡾⠋⠁⠀⠈⠀⠉⠛⢿⣿⡿⠟⠉⢀⡠⠖⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠀⠀⠀⠄⠀⠀⠀⠀⠀⠀⠀⠦⣿⠷⣦⣇⣀⣠⡾⠂⠀⠀⠀
⠀        ⠀⠀⠀⠀⠑⠀⠀⠀⠘⠀⢹⢽⠛⠉⠉⢣⠀⠀⠀⢁⠀⠀⠀⢠⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⣿⠀⠀⢀⣴⣆⠀⠀⠀⠈⣿⡏⠐⠈⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⠀⠀⠀⠈⡃⡂⠀⠀⣰⠀⠠⣾⣿⠆⠀⠉⢧⠽⠀⠀⠀⠀⠀
⠀        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⡘⠶⢿⡅⠠⠤⠜⠀⠀⠀⡌⠀⠀⢀⠣⡧⣃⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠸⠃⠀⠀⠀⠀⢙⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢨⠀⣅⣾⣦⡈⣱⢀⠀⠀⠀⠀⠀⠀⠀
⠀        ⠀⠀ ⠀⠀⠀⠀⣤⡄⠀⣄⣀⣨⣛⠦⣀⣀⣠⢤⣟⣀⣀⣀⣀⣸⡵⠇⣐⣀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⠀⢠⣿⡽⡻⢤⣖⣀⣹⢈⡀⠀⠀
⠀        ⠀⠀ ⠁⠈⠁⠉⠉⠉⠹⡊⢹⡗⠋⠒⣍⠋⣝⠏⠉⢭⡌⠉⢹⣹⣶⡇⡏⠀⠀⢀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⢊⣾⣗⢒⡖⠛⣿⡿⠛⠳⠏⠁
⠀        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⢧⣀⡀⠸⢽⡾⢳⡲⣏⠀⢶⡚⡾⣦⢣⠒⠒⣀⠞⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢹⠁⠀⠀⢰⣼⣿⠓⠠⠀⠀
⠀        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⠂⠀⠘⠑⠻⡿⠷⠷⣿⠶⠒⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢤⠁⠀⠀⠀⠐⠄⠀⠀⠠⠤⠀⡀⠠⡿⢧⣴⠇⠀
⠀        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠀⠀⠀⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⢀⠀⠀⠀⠅⠀⠀⠀⠀⠠⠒⠀⢀⠈⠘⠀⣰⠃⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀         ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢄⠁⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠁⠀⠀⠀⠀⠀
⠀        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠄⠒⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀            ⠀⠀⠀⠀⠀⠀
                    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀            >> SYSTEM INITIALIZATION SEQUENCE <<
EOF
)
ASCII_ART_END=$(cat << "EOF"
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⠆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣭⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣹⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣤⠤⢤⣀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⠴⠒⢋⣉⣀⣠⣄⣀⣈⡇
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣴⣾⣯⠴⠚⠉⠉⠀⠀⠀⠀⣤⠏⣿
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡿⡇⠁⠀⠀⠀⠀⡄⠀⠀⠀⠀⠀⠀⠀⠀⣠⣴⡿⠿⢛⠁⠁⣸⠀⠀⠀⠀⠀⣤⣾⠵⠚⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠰⢦⡀⠀⣠⠀⡇⢧⠀⠀⢀⣠⡾⡇⠀⠀⠀⠀⠀⣠⣴⠿⠋⠁⠀⠀⠀⠀⠘⣿⠀⣀⡠⠞⠛⠁⠂⠁⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡈⣻⡦⣞⡿⣷⠸⣄⣡⢾⡿⠁⠀⠀⠀⣀⣴⠟⠋⠁⠀⠀⠀⠀⠐⠠⡤⣾⣙⣶⡶⠃⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣂⡷⠰⣔⣾⣖⣾⡷⢿⣐⣀⣀⣤⢾⣋⠁⠀⠀⠀⣀⢀⣀⣀⣀⣀⠀⢀⢿⠑⠃⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠠⡦⠴⠴⠤⠦⠤⠤⠤⠤⠤⠴⠶⢾⣽⣙⠒⢺⣿⣿⣿⣿⢾⠶⣧⡼⢏⠑⠚⠋⠉⠉⡉⡉⠉⠉⠹⠈⠁⠉⠀⠨⢾⡂⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠂⠀⠀⠀⠂⠐⠀⠀⠀⠈⣇⡿⢯⢻⣟⣇⣷⣞⡛⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣠⣆⠀⠀⠀⠀⢠⡷⡛⣛⣼⣿⠟⠙⣧⠅⡄⠀⠀⠀⠀⠀⠀⠰⡆⠀⠀⠀⠀⢠⣾⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣴⢶⠏⠉⠀⠀⠀⠀⠀⠿⢠⣴⡟⡗⡾⡒⠖⠉⠏⠁⠀⠀⠀⠀⣀⢀⣠⣧⣀⣀⠀⠀⠀⠚⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⢴⣿⠟⠁⠀⠀⠀⠀⠀⠀⠀⣠⣷⢿⠋⠁⣿⡏⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⣿⢭⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⢏⡵⠛⠀⠀⠀⠀⠀⠀⠀⣀⣴⠞⠛⠀⠀⠀⠀⢿⠀⠂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠂⢿⠘⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣼⠛⣲⡏⠁⠀⠀⠀⠀⠀⢀⣠⡾⠋⠉⠀⠀⠀⠀⠀⠀⢾⡅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⡴⠟⠀⢰⡯⠄⠀⠀⠀⠀⣠⢴⠟⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⣹⠆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⡾⠁⠁⠀⠘⠧⠤⢤⣤⠶⠏⠙⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢾⡃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠘⣇⠂⢀⣀⣀⠤⠞⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠾⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢼⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢰⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠛⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                       >> INITIALIZATION END <<
EOF
)

# =========================================================
# 1. SETUP TERMINAL UI & PRINT START ART
# =========================================================
clear
printf "\033[H" # Move cursor to top left

# Safely print top padding for START art
for ((p=0; p<START_ART_PADDING_TOP; p++)); do echo ""; done

print_centered "$ASCII_ART_START"

# Safely print bottom padding for START art
for ((p=0; p<START_ART_PADDING_BOTTOM; p++)); do echo ""; done

if [ -f "$AUDIO_OS_START" ]; then
    $AUDIO_PLAYER "$AUDIO_OS_START" >/dev/null 2>&1 &
fi

# Calculate exactly how much vertical space the START art and padding consumed
term_lines=$(tput lines 2>/dev/null || echo 40)
art_lines=$(echo "$ASCII_ART_START" | wc -l)
total_art_height=$(( START_ART_PADDING_TOP + art_lines + START_ART_PADDING_BOTTOM ))

# The scrolling log section should start 1 line below the padded art
scroll_start=$((total_art_height + 1))

# NEW FIX: If the art is too big, reserve the bottom 6 lines for logs.
if (( scroll_start >= term_lines )); then
    scroll_start=$((term_lines - 6))
fi

# Absolute failsafe
if (( scroll_start < 2 )); then
    scroll_start=2
fi

printf "\033[%d;%dr" "$scroll_start" "$term_lines"
printf "\033[%d;1H" "$scroll_start" # Move cursor into the scroll area

# =========================================================
# 2. RUN STARTUP LOGIC (Logs will scroll safely below art)
# =========================================================
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

# =========================================================
# 3. TRANSITION TO END ART
# =========================================================
# Reset terminal scrolling region to normal
printf "\033[r"
# Clear the screen completely
clear

# Print top padding for END art
for ((p=0; p<END_ART_PADDING_TOP; p++)); do echo ""; done

print_centered "$ASCII_ART_END"

# Print bottom padding for END art
for ((p=0; p<END_ART_PADDING_BOTTOM; p++)); do echo ""; done

for ((i = AUTO_CLOSE_AFTER; i >= 1; i--)); do
    sleep 1
    elapsed=$((elapsed + 1))

    printf "\rAutoclose in %ds   " "$i"
    printf '[%02ds] %s\n' "$elapsed" "closing popup in ${i}s" >> "$BG_LOG"
done

echo ""
exit 0
