#!/usr/bin/env bash
# Waybar Timer / Pomodoro (hardened)
# Goals:
# - Never crash Waybar: always output valid JSON in daemon mode, never print noise to stdout/stderr
# - Always exit 0 in controller mode
# - Robust state handling (atomic writes, corruption recovery)
# - Stable FIFO (single path) + singleton daemon
# - JSON-safe escaping

# -------------------- HARDENING --------------------
set -u
set -o pipefail

DEBUG="${DEBUG:-0}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
LOG_FILE="${RUNTIME_DIR}/waybar_timer.log"
NOTIFY_EXPIRED_TIME_FAST=1000
NOTIFY_EXPIRED_TIME_MEDIUM=2000
NOTIFY_EXPIRED_TIME_LONG=3000

log() {
  (( DEBUG )) || return 0
  printf '[%s] %s\n' "$(date -Is)" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

json_escape() {
  local s="${1:-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/}
  printf '%s' "$s"
}

# Always exit 0 (Waybar-safe)
graceful_exit() { log "exit: $*"; exit 0; }

# If something unexpected happens in daemon mode, emit valid JSON then exit 0
on_err() {
  local ec=$?
  log "ERR exit=$ec line=${BASH_LINENO[0]} cmd=${BASH_COMMAND}"
  if [ "${__DAEMON_MODE:-0}" = "1" ]; then
    printf '{"text":"󰔞","tooltip":"Timer error (see log)","class":"error"}\n'
  fi
  exit 0
}
trap on_err ERR

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# -------------------- CONFIGURATION --------------------

# --- STANDARD TIMER PRESETS (Seconds) ---
PRESETS=(60 300 600 900 1200 1500 1800 2700 3000 3600 4500 5400 6300 7200 9000 10800)
SCROLL_STEP=60
INACTIVITY_LIMIT=30

# --- POMODORO PRESET ---
POMO_PRESETS=(
  "50 8 4"
)

# Pomodoro Settings
POMO_ENABLED=true
POMO_AUTO_BREAK=true
POMO_AUTO_WORK=true

# --- SOUND EFFECTS ---
SOUND_TIMER_DONE="${HOME}/.config/waybar/sounds/seasion_done.wav"
SOUND_WORK_START="${HOME}/.config/waybar/sounds/work_on.wav"
SOUND_BREAK_START="${HOME}/.config/waybar/sounds/break_time.wav"
SOUND_BREAK_END="${HOME}/.config/waybar/sounds/break_end.wav"
SOUND_COMPLETE="${HOME}/.config/waybar/sounds/seasion_done.wav"

# --- ICONS ---
ICON_DISABLED="󰔞 "
ICON_IDLE="󰔛"
ICON_SELECT="󱫣"
ICON_PAUSE="󱫟"
ICON_RUNNING="󱫡"
ICON_WARNING="󱫍"
ICON_DONE="󱫑"
ICON_RESET="󱫥"

# Pomodoro Icons
ICON_POMO_IDLE=""
ICON_POMO_START=""
ICON_POMO_HALF=""
ICON_POMO_END=""
ICON_POMO_DONE=""
ICON_POMO_BREAK=""

# State / IPC (stable paths)
STATE_FILE="/dev/shm/waybar_timer.json"
PIPE_FILE="/tmp/waybar_timer.fifo"
PID_FILE="/tmp/waybar_timer.pid"

# -------------------- SOUND --------------------
play_sound() {
  local sound_file="${1:-}"
  sound_file="${sound_file/#\~/$HOME}"
  [ -n "$sound_file" ] || return 0
  [ -f "$sound_file" ] || { log "sound missing: $sound_file"; return 0; }

  if have_cmd paplay; then
    paplay "$sound_file" >/dev/null 2>&1 &
  elif have_cmd pw-play; then
    pw-play "$sound_file" >/dev/null 2>&1 &
  else
    log "no paplay/pw-play available"
  fi
}

notify() {
  # notify-send wrapper: never blocks, never outputs
  have_cmd notify-send || return 0
  notify-send "$@" >/dev/null 2>&1 &
}

# -------------------- STATE MANAGEMENT --------------------
init_state() {
  printf -v NOW '%(%s)T' -1
  # STATE|SEC_SET|START_TIME|PAUSE_REM|LAST_ACT|PRESET_IDX|MODE|P_STAGE|P_CURRENT|P_TOTAL|P_WORK_LEN|P_BREAK_LEN|P_EDIT_FOCUS
  printf '%s\n' "DISABLED|0|0|0|$NOW|0|0|0|1|1|5|1|0" >"$STATE_FILE" 2>/dev/null || true
}

read_state() {
  if [ ! -f "$STATE_FILE" ]; then
    init_state
  fi

  local raw
  raw="$(cat "$STATE_FILE" 2>/dev/null || true)"

  IFS='|' read -r STATE SEC_SET START_TIME PAUSE_REM LAST_ACT PRESET_IDX MODE P_STAGE P_CURRENT P_TOTAL P_WORK_LEN P_BREAK_LEN P_EDIT_FOCUS <<<"$raw"

  # If anything essential is missing, re-init
  if [ -z "${STATE:-}" ] || [ -z "${SEC_SET:-}" ] || [ -z "${LAST_ACT:-}" ] || [ -z "${P_EDIT_FOCUS:-}" ]; then
    log "state corrupt -> reinit: $raw"
    init_state
    raw="$(cat "$STATE_FILE" 2>/dev/null || true)"
    IFS='|' read -r STATE SEC_SET START_TIME PAUSE_REM LAST_ACT PRESET_IDX MODE P_STAGE P_CURRENT P_TOTAL P_WORK_LEN P_BREAK_LEN P_EDIT_FOCUS <<<"$raw"
  fi

  # Defensive defaults (avoid unbound / non-numeric surprises)
  SEC_SET="${SEC_SET:-0}"
  START_TIME="${START_TIME:-0}"
  PAUSE_REM="${PAUSE_REM:-0}"
  LAST_ACT="${LAST_ACT:-0}"
  PRESET_IDX="${PRESET_IDX:-0}"
  MODE="${MODE:-0}"
  P_STAGE="${P_STAGE:-0}"
  P_CURRENT="${P_CURRENT:-1}"
  P_TOTAL="${P_TOTAL:-1}"
  P_WORK_LEN="${P_WORK_LEN:-5}"
  P_BREAK_LEN="${P_BREAK_LEN:-1}"
  P_EDIT_FOCUS="${P_EDIT_FOCUS:-0}"
}

write_state() {
  # Atomic write to avoid corruption
  local tmp="${STATE_FILE}.$$"
  printf '%s\n' "$1|$2|$3|$4|$5|$6|$7|$8|$9|${10}|${11}|${12}|${13}" >"$tmp" 2>/dev/null || true
  mv -f "$tmp" "$STATE_FILE" 2>/dev/null || true
}

WS() { write_state "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" "${13}"; }

format_time() {
  local T="${1:-0}"
  local HH=$((T / 3600))
  local MM=$(((T % 3600) / 60))
  local SS=$((T % 60))
  if [ "$HH" -gt 0 ]; then
    printf "%d:%02d:%02d" "$HH" "$MM" "$SS"
  else
    printf "%02d:%02d" "$MM" "$SS"
  fi
}

trigger_update() {
  # Ping daemon through single FIFO; ignore failures
  [ -p "$PIPE_FILE" ] && printf '1\n' >"$PIPE_FILE" 2>/dev/null || true
}

# -------------------- CONTROLLER MODE --------------------
if [ -n "${1:-}" ]; then
  [ -f "$STATE_FILE" ] || init_state
  read_state

  printf -v NOW '%(%s)T' -1
  NEW_ACT="$NOW"

  # If pomodoro disabled but mode is pomodoro, reset to idle safely
  if [ "$POMO_ENABLED" != true ] && [ "$MODE" = "1" ]; then
    WS "IDLE" "0" "0" "0" "$NEW_ACT" "0" "0" "0" "0" "0" "0" "0" "0"
    read_state
  fi

  case "$1" in
  "toggle")
    if [ "$STATE" = "RUNNING" ]; then
      ELAPSED=$((NOW - START_TIME))
      REM=$((SEC_SET - ELAPSED))
      WS "PAUSED" "$SEC_SET" "0" "$REM" "$NEW_ACT" "$PRESET_IDX" "$MODE" "$P_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
    elif [ "$STATE" = "PAUSED" ]; then
      NEW_START=$((NOW - SEC_SET + PAUSE_REM))
      WS "RUNNING" "$SEC_SET" "$NEW_START" "0" "$NEW_ACT" "$PRESET_IDX" "$MODE" "$P_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
    fi
    trigger_update
    graceful_exit "toggle"
    ;;

  "pause")
    if [ "$STATE" = "RUNNING" ]; then
      ELAPSED=$((NOW - START_TIME))
      REM=$((SEC_SET - ELAPSED))
      WS "PAUSED" "$SEC_SET" "0" "$REM" "$NEW_ACT" "$PRESET_IDX" "$MODE" "$P_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
      trigger_update
    fi
    graceful_exit "pause"
    ;;

  "resume")
    if [ "$STATE" = "PAUSED" ]; then
      NEW_START=$((NOW - SEC_SET + PAUSE_REM))
      WS "RUNNING" "$SEC_SET" "$NEW_START" "0" "$NEW_ACT" "$PRESET_IDX" "$MODE" "$P_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
      trigger_update
    fi
    graceful_exit "resume"
    ;;

  "reset")
    WS "RESET_ANIM" "0" "0" "0" "$NEW_ACT" "0" "0" "0" "0" "0" "0" "0" "0"
    trigger_update
    graceful_exit "reset"
    ;;

  "skip")
    if [ "$MODE" = "1" ] && { [ "$STATE" = "RUNNING" ] || [ "$STATE" = "PAUSED" ]; }; then
      if [ "$P_STAGE" = "0" ]; then
        play_sound "$SOUND_BREAK_START"
        notify -u normal -t $NOTIFY_EXPIRED_TIME_MEDIUM -i tea "Pomodoro" "Work Session Skipped! Starting Break."
        NEW_STAGE=1
        NEW_SET=$((P_BREAK_LEN * 60))
        if [ "$POMO_AUTO_BREAK" = true ]; then
          WS "POMO_MSG" "$NEW_SET" "$NOW" "0" "$NOW" "$PRESET_IDX" "1" "$NEW_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
        else
          WS "PAUSED" "$NEW_SET" "0" "$NEW_SET" "$NOW" "$PRESET_IDX" "1" "$NEW_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
        fi
      else
        NEW_CURRENT=$((P_CURRENT + 1))
        if [ "$NEW_CURRENT" -gt "$P_TOTAL" ]; then
          play_sound "$SOUND_COMPLETE"
          notify -u normal -t $NOTIFY_EXPIRED_TIME_LONG -i trophy "Pomodoro" "All Sessions Completed!"
          WS "DONE" "0" "0" "0" "$NOW" "0" "1" "0" "$P_TOTAL" "$P_TOTAL" "0" "0" "0"
        else
          play_sound "$SOUND_WORK_START"
          notify -u normal -t $NOTIFY_EXPIRED_TIME_MEDIUM -i clock "Pomodoro" "Break Skipped! Starting Work Session $NEW_CURRENT/$P_TOTAL."
          NEW_STAGE=0
          NEW_SET=$((P_WORK_LEN * 60))
          if [ "$POMO_AUTO_WORK" = true ]; then
            WS "POMO_MSG" "$NEW_SET" "$NOW" "0" "$NOW" "$PRESET_IDX" "1" "$NEW_STAGE" "$NEW_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
          else
            WS "PAUSED" "$NEW_SET" "0" "$NEW_SET" "$NOW" "$PRESET_IDX" "1" "$NEW_STAGE" "$NEW_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
          fi
        fi
      fi
      trigger_update
    fi
    graceful_exit "skip"
    ;;

  "pomo")
    if [ "$POMO_ENABLED" != true ]; then
      graceful_exit "pomo disabled"
    fi
    shift
    ARGS="$*"

    W=25
    B=5
    S=4

    if [[ "$ARGS" =~ [0-9]+[mbs] ]]; then
      [[ "$ARGS" =~ ([0-9]+)m ]] && W="${BASH_REMATCH[1]}"
      [[ "$ARGS" =~ ([0-9]+)b ]] && B="${BASH_REMATCH[1]}"
      [[ "$ARGS" =~ ([0-9]+)s ]] && S="${BASH_REMATCH[1]}"
    else
      [ -n "${1:-}" ] && W="$1"
      [ -n "${2:-}" ] && B="$2"
      [ -n "${3:-}" ] && S="$3"
    fi

    [ "$W" -lt 1 ] && W=1
    [ "$B" -lt 1 ] && B=1
    [ "$S" -lt 1 ] && S=1

    WS "POMO_MSG" "$((W * 60))" "$NOW" "0" "$NEW_ACT" "0" "1" "0" "1" "$S" "$W" "$B" "0"
    trigger_update
    graceful_exit "pomo"
    ;;

  "up" | "down")
    MOD=$SCROLL_STEP
    [ "$1" = "down" ] && MOD=$((-SCROLL_STEP))

    if [ "$STATE" = "IDLE" ]; then
      if [ "$POMO_ENABLED" = true ] && [ "$1" = "down" ]; then
        read -r w b s <<<"${POMO_PRESETS[0]}"
        WS "SELECT" "$((w * 60))" "0" "0" "$NEW_ACT" "0" "1" "0" "1" "$s" "$w" "$b" "0"
      else
        WS "SELECT" "0" "0" "0" "$NEW_ACT" "0" "0" "0" "0" "0" "0" "0" "0"
      fi
      trigger_update
      graceful_exit "scroll from idle"
    fi

    if [ "$STATE" = "SELECT" ]; then
      if [ "$MODE" = "0" ]; then
        NEW_SET=$((SEC_SET + MOD))
        if [ "$NEW_SET" -lt 30 ]; then
          WS "IDLE" "0" "0" "0" "$NEW_ACT" "0" "0" "0" "0" "0" "0" "0" "0"
        else
          WS "SELECT" "$NEW_SET" "0" "0" "$NEW_ACT" "$PRESET_IDX" "0" "0" "0" "0" "0" "0" "0"
        fi
      else
        case "$P_EDIT_FOCUS" in
        0)
          NEW_W=$((P_WORK_LEN + (MOD / 60)))
          if [ "$NEW_W" -lt 1 ]; then
            WS "IDLE" "0" "0" "0" "$NEW_ACT" "0" "0" "0" "0" "0" "0" "0" "0"
          else
            NEW_SET=$((NEW_W * 60))
            WS "SELECT" "$NEW_SET" "0" "0" "$NEW_ACT" "$PRESET_IDX" "1" "0" "1" "$P_TOTAL" "$NEW_W" "$P_BREAK_LEN" "0"
          fi
          ;;
        1)
          NEW_B=$((P_BREAK_LEN + (MOD / 60)))
          [ "$NEW_B" -lt 1 ] && NEW_B=1
          WS "SELECT" "$SEC_SET" "0" "0" "$NEW_ACT" "$PRESET_IDX" "1" "0" "1" "$P_TOTAL" "$P_WORK_LEN" "$NEW_B" "1"
          ;;
        2)
          S_MOD=1
          [ "$1" = "down" ] && S_MOD=-1
          NEW_S=$((P_TOTAL + S_MOD))
          [ "$NEW_S" -lt 1 ] && NEW_S=1
          WS "SELECT" "$SEC_SET" "0" "0" "$NEW_ACT" "$PRESET_IDX" "1" "0" "1" "$NEW_S" "$P_WORK_LEN" "$P_BREAK_LEN" "2"
          ;;
        esac
      fi
      trigger_update
      graceful_exit "scroll in select"
    fi

    if [ "$STATE" = "RUNNING" ]; then
      ELAPSED=$((NOW - START_TIME))
      REM=$((SEC_SET - ELAPSED))
      NEW_REM=$((REM + MOD))
      [ "$NEW_REM" -le 0 ] && NEW_REM=1
      NEW_SET=$((NEW_REM + (NOW - START_TIME)))
      WS "RUNNING" "$NEW_SET" "$START_TIME" "0" "$NEW_ACT" "$PRESET_IDX" "$MODE" "$P_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
    elif [ "$STATE" = "PAUSED" ]; then
      NEW_REM=$((PAUSE_REM + MOD))
      [ "$NEW_REM" -lt 1 ] && NEW_REM=60
      WS "PAUSED" "$SEC_SET" "0" "$NEW_REM" "$NEW_ACT" "$PRESET_IDX" "$MODE" "$P_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
    fi
    trigger_update
    graceful_exit "scroll running/paused"
    ;;

  "click")
    case "$STATE" in
    "DISABLED") WS "IDLE" "0" "0" "0" "$NEW_ACT" "0" "0" "0" "0" "0" "0" "0" "0" ;;
    "IDLE") WS "SELECT" "0" "0" "0" "$NEW_ACT" "0" "0" "0" "0" "0" "0" "0" "0" ;;
    "SELECT")
      if [ "$MODE" = "1" ]; then
        WS "POMO_MSG" "$SEC_SET" "$NOW" "0" "$NEW_ACT" "$PRESET_IDX" "1" "0" "1" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
      else
        WS "RUNNING" "$SEC_SET" "$NOW" "0" "$NEW_ACT" "$PRESET_IDX" "0" "0" "0" "0" "0" "0" "0"
      fi
      ;;
    "RUNNING")
      ELAPSED=$((NOW - START_TIME))
      REM=$((SEC_SET - ELAPSED))
      WS "PAUSED" "$SEC_SET" "0" "$REM" "$NEW_ACT" "$PRESET_IDX" "$MODE" "$P_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
      ;;
    "PAUSED")
      NEW_START=$((NOW - SEC_SET + PAUSE_REM))
      WS "RUNNING" "$SEC_SET" "$NEW_START" "0" "$NEW_ACT" "$PRESET_IDX" "$MODE" "$P_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
      ;;
    "DONE") WS "IDLE" "0" "0" "0" "$NEW_ACT" "0" "0" "0" "0" "0" "0" "0" "0" ;;
    esac
    trigger_update
    graceful_exit "click"
    ;;

  "right")
    if [ "$MODE" = "1" ] && { [ "$STATE" = "RUNNING" ] || [ "$STATE" = "PAUSED" ]; }; then
      "$0" skip >/dev/null 2>&1 || true
      graceful_exit "right->skip"
    elif [ "$STATE" = "IDLE" ]; then
      WS "DISABLED" "0" "0" "0" "$NEW_ACT" "0" "0" "0" "0" "0" "0" "0" "0"
    elif [ "$STATE" = "SELECT" ]; then
      if [ "$MODE" = "0" ]; then
        if [ "$SEC_SET" -eq 0 ]; then
          NEXT=0
        else
          NEXT=$((PRESET_IDX + 1))
          [ "$NEXT" -ge "${#PRESETS[@]}" ] && NEXT=0
        fi
        NEW_TIME="${PRESETS[$NEXT]}"
        WS "SELECT" "$NEW_TIME" "0" "0" "$NEW_ACT" "$NEXT" "0" "0" "0" "0" "0" "0" "0"
      else
        if [ "$P_EDIT_FOCUS" = "0" ]; then
          WS "SELECT" "$SEC_SET" "0" "0" "$NEW_ACT" "$PRESET_IDX" "1" "0" "1" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "1"
        elif [ "$P_EDIT_FOCUS" = "1" ]; then
          WS "SELECT" "$SEC_SET" "0" "0" "$NEW_ACT" "$PRESET_IDX" "1" "0" "1" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "2"
        else
          WS "SELECT" "$SEC_SET" "0" "0" "$NEW_ACT" "$PRESET_IDX" "1" "0" "1" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "0"
        fi
      fi
    elif [ "$STATE" = "RUNNING" ] || [ "$STATE" = "PAUSED" ]; then
      "$0" click >/dev/null 2>&1 || true
      graceful_exit "right->click"
    fi
    trigger_update
    graceful_exit "right"
    ;;

  "middle")
    WS "RESET_ANIM" "0" "0" "0" "$NEW_ACT" "0" "0" "0" "0" "0" "0" "0" "0"
    trigger_update
    graceful_exit "middle"
    ;;

  *)
    INPUT="$1"
    SECONDS=0

    if [[ "$INPUT" =~ ([0-9]+)h ]]; then SECONDS=$((SECONDS + ${BASH_REMATCH[1]} * 3600)); fi
    if [[ "$INPUT" =~ ([0-9]+)m ]]; then SECONDS=$((SECONDS + ${BASH_REMATCH[1]} * 60)); fi
    if [[ "$INPUT" =~ ([0-9]+)s ]]; then
      SECONDS=$((SECONDS + ${BASH_REMATCH[1]}))
    elif [[ "$INPUT" =~ ^[0-9]+$ ]]; then
      if [[ ! "$INPUT" =~ [hm] ]]; then
        SECONDS=$INPUT
      fi
    fi

    if [ "$SECONDS" -gt 0 ]; then
      WS "RUNNING" "$SECONDS" "$NOW" "0" "$NEW_ACT" "0" "0" "0" "0" "0" "0" "0" "0"
      trigger_update
    fi
    graceful_exit "set seconds"
    ;;
  esac

  trigger_update
  graceful_exit "controller default"
fi

# -------------------- DAEMON MODE --------------------
__DAEMON_MODE=1

cleanup() {
  exec 3>&- 2>/dev/null || true
  if [ "$(cat "$PID_FILE" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$PIPE_FILE" "$PID_FILE" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup SIGTERM SIGINT EXIT

# Singleton daemon
if [ -f "$PID_FILE" ]; then
  oldpid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    # Another daemon is already running; exit cleanly.
    graceful_exit "daemon already running pid=$oldpid"
  fi
fi
printf '%s\n' "$$" >"$PID_FILE" 2>/dev/null || true

[ -f "$STATE_FILE" ] || init_state
[ -p "$PIPE_FILE" ] || mkfifo "$PIPE_FILE" 2>/dev/null || true

exec 3<> "$PIPE_FILE"

while true; do
  # If parent Waybar died, exit
  if ! kill -0 "$PPID" 2>/dev/null; then
    cleanup
  fi

  read_state
  printf -v NOW '%(%s)T' -1

  if [ "$POMO_ENABLED" != true ] && [ "$MODE" = "1" ]; then
    WS "IDLE" "0" "0" "0" "$NOW" "0" "0" "0" "0" "0" "0" "0" "0"
    read_state
  fi

  TEXT=""
  ICON=""
  CLASS="$STATE"
  TOOLTIP=""

  case "$STATE" in
  "DISABLED")
    ICON="$ICON_DISABLED"
    CLASS="disabled"
    TOOLTIP="Timer Disabled\nLeft Click: Activate"
    ;;
  "IDLE")
    ICON="$ICON_IDLE"
    TEXT="00:00"
    CLASS="idle"
    if [ "$POMO_ENABLED" = true ]; then
      TOOLTIP="Timer Idle\nScroll Up: Pomodoro Mode\nScroll Down: Standard Timer\nLeft Click: Set Timer\nRight Click: Disable"
    else
      TOOLTIP="Timer Idle\nScroll: Standard Timer\nLeft Click: Set Timer\nRight Click: Disable"
    fi

    if [ $((NOW - LAST_ACT)) -gt "$INACTIVITY_LIMIT" ]; then
      WS "DISABLED" "0" "0" "0" "$NOW" "0" "0" "0" "0" "0" "0" "0" "0"
      trigger_update
      # fall through to print updated state next loop
    fi
    ;;
  "SELECT")
    if [ "$MODE" = "0" ]; then
      ICON="$ICON_SELECT"
      TEXT="$(format_time "$SEC_SET")"
      TOOLTIP="Timer Mode\nLeft Click: Start\nRight Click: Next Preset\nScroll: Adjust Time (± 1m)\nScroll < 1m: Exit (Idle)"
    else
      ICON="$ICON_POMO_IDLE"
      if [ "$P_EDIT_FOCUS" = "1" ]; then
        TEXT="${P_WORK_LEN}m | [${P_BREAK_LEN}]b | ${P_TOTAL}s"
        TOOLTIP="Editing Break Time\nScroll: Change Break (± 1m)\nRight Click: Edit Sessions"
      elif [ "$P_EDIT_FOCUS" = "2" ]; then
        TEXT="${P_WORK_LEN}m | ${P_BREAK_LEN}b | [${P_TOTAL}]s"
        TOOLTIP="Editing Sessions\nScroll: Change Sessions (± 1)\nRight Click: Edit Minutes"
      else
        TEXT="[${P_WORK_LEN}]m | ${P_BREAK_LEN}b | ${P_TOTAL}s"
        TOOLTIP="Pomodoro Mode\nScroll: Adjust Minutes (± 1m)\nScroll < 1m: Exit (Idle)\nRight Click: Edit Break Time"
      fi
    fi
    CLASS="select"

    if [ $((NOW - LAST_ACT)) -gt "$INACTIVITY_LIMIT" ]; then
      WS "DISABLED" "0" "0" "0" "$NOW" "0" "0" "0" "0" "0" "0" "0" "0"
      trigger_update
    fi
    ;;
  "POMO_MSG")
    if [ "$P_STAGE" = "0" ]; then
      TEXT="Work $P_CURRENT/$P_TOTAL"
      ICON="$ICON_POMO_START"
    else
      TEXT="Break Time"
      ICON="$ICON_POMO_BREAK"
    fi

    printf '{"text":"%s","tooltip":"","class":"pomo_msg"}\n' "$(json_escape "$ICON $TEXT")"
    sleep 1.2

    # Start running immediately after message
    WS "RUNNING" "$SEC_SET" "$NOW" "0" "$NOW" "$PRESET_IDX" "$MODE" "$P_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
    continue
    ;;
  "RUNNING")
    ELAPSED=$((NOW - START_TIME))
    REM=$((SEC_SET - ELAPSED))

    if [ "$REM" -le 0 ]; then
      if [ "$MODE" = "0" ]; then
        play_sound "$SOUND_TIMER_DONE"
        notify -u normal -t $NOTIFY_EXPIRED_TIME_MEDIUM -i clock "Timer" "Timer Finished!"
        WS "DONE" "$SEC_SET" "0" "0" "$NOW" "0" "0" "0" "0" "0" "0" "0" "0"
      else
        if [ "$P_STAGE" = "0" ]; then
          play_sound "$SOUND_BREAK_START"
          notify -u normal -t $NOTIFY_EXPIRED_TIME_MEDIUM -i tea "Pomodoro" "Work Session $P_CURRENT/$P_TOTAL Finished! Time for a Break."
          NEW_STAGE=1
          NEW_SET=$((P_BREAK_LEN * 60))
          if [ "$POMO_AUTO_BREAK" = true ]; then
            WS "POMO_MSG" "$NEW_SET" "$NOW" "0" "$NOW" "$PRESET_IDX" "1" "$NEW_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
          else
            WS "PAUSED" "$NEW_SET" "0" "$NEW_SET" "$NOW" "$PRESET_IDX" "1" "$NEW_STAGE" "$P_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
          fi
        else
          NEW_CURRENT=$((P_CURRENT + 1))
          if [ "$NEW_CURRENT" -gt "$P_TOTAL" ]; then
            play_sound "$SOUND_COMPLETE"
            notify -u normal -t $NOTIFY_EXPIRED_TIME_LONG -i trophy "Pomodoro" "All Sessions Completed!"
            WS "DONE" "0" "0" "0" "$NOW" "0" "1" "0" "$P_TOTAL" "$P_TOTAL" "0" "0" "0"
          else
            play_sound "$SOUND_WORK_START"
            notify -u normal -t $NOTIFY_EXPIRED_TIME_MEDIUM -i clock "Pomodoro" "Break Finished! Back to work."
            NEW_STAGE=0
            NEW_SET=$((P_WORK_LEN * 60))
            if [ "$POMO_AUTO_WORK" = true ]; then
              WS "POMO_MSG" "$NEW_SET" "$NOW" "0" "$NOW" "$PRESET_IDX" "1" "$NEW_STAGE" "$NEW_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
            else
              WS "PAUSED" "$NEW_SET" "0" "$NEW_SET" "$NOW" "$PRESET_IDX" "1" "$NEW_STAGE" "$NEW_CURRENT" "$P_TOTAL" "$P_WORK_LEN" "$P_BREAK_LEN" "$P_EDIT_FOCUS"
            fi
          fi
        fi
      fi
      trigger_update
      continue
    fi

    if [ "$MODE" = "1" ]; then
      if [ "$P_STAGE" = "1" ]; then
        ICON="$ICON_POMO_BREAK"
        CLASS="pomo_break"
      else
        TOTAL_DUR=$((P_WORK_LEN * 60))
        if [ "$REM" -lt 30 ]; then
          ICON="$ICON_POMO_END"
          CLASS="warning"
        elif [ "$REM" -le $((TOTAL_DUR / 2)) ]; then
          ICON="$ICON_POMO_HALF"
          CLASS="running"
        else
          ICON="$ICON_POMO_START"
          CLASS="running"
        fi
      fi
      TOOLTIP="Pomodoro: $([ "$P_STAGE" = 0 ] && echo Work || echo Break) ($P_CURRENT/$P_TOTAL)\nLeft Click: Pause\nRight Click: Skip Session\nScroll: Adjust Time (± 1m)\nMiddle Click: Reset"
    else
      if [ "$REM" -le 30 ]; then
        ICON="$ICON_WARNING"
        CLASS="warning"
      else
        ICON="$ICON_RUNNING"
        CLASS="running"
      fi
      TOOLTIP="Timer Running\nLeft Click: Pause\nMiddle Click: Reset\nScroll: Adjust Time (± 1m)"
    fi

    TEXT="$(format_time "$REM")"
    ;;
  "PAUSED")
    if [ "$MODE" = "1" ]; then
      ICON="$ICON_POMO_BREAK"
      TOOLTIP="Pomodoro Paused\nLeft Click: Resume\nRight Click: Skip Session\nScroll: Adjust Time (± 1m)\nMiddle Click: Reset"
    else
      ICON="$ICON_PAUSE"
      TOOLTIP="Timer Paused\nLeft Click: Resume\nScroll: Adjust Time (± 1m)\nMiddle Click: Reset"
    fi
    TEXT="$(format_time "$PAUSE_REM")"
    CLASS="paused"
    ;;
  "DONE")
    if [ "$MODE" = "1" ]; then
      ICON="$ICON_POMO_DONE"
      TOOLTIP="Pomodoro Complete"
    else
      ICON="$ICON_DONE"
      TOOLTIP="Timer Finished"
    fi
    TEXT="00:00"
    CLASS="done"
    if [ $((NOW - LAST_ACT)) -gt 5 ]; then
      WS "IDLE" "0" "0" "0" "$NOW" "0" "0" "0" "0" "0" "0" "0" "0"
      trigger_update
      continue
    fi
    ;;
  "RESET_ANIM")
    printf '{"text":"%s","tooltip":"%s","class":"reset"}\n' \
      "$(json_escape "$ICON_RESET --:--")" \
      "$(json_escape "Resetting...")"
    sleep 0.2
    WS "IDLE" "0" "0" "0" "$NOW" "0" "0" "0" "0" "0" "0" "0" "0"
    continue
    ;;
  esac

  # Always print valid JSON
  printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
    "$(json_escape "$ICON $TEXT")" \
    "$(json_escape "$TOOLTIP")" \
    "$(json_escape "$CLASS")"

  # Wait either for FIFO ping or timeout (1s tick)
  # If there is no writer, read returns after timeout.
  read -t 1 -n 1 _ <&3 2>/dev/null || true
done
