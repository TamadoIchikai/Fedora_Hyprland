#!/usr/bin/env bash
#
# update-check.sh - one-shot login update checker.
#
# Runs once per login from autostart.sh, checks only apps that registered
# themselves in ~/.config/installSH/flags/*.env, always produces a result, and
# exits. It never starts a daemon and never applies updates automatically.
#
# Primary output: notify-send.
# Fallback output: foot popup via ~/.local/bin/update-check-popup.sh, placed
# with WM_exec_floating from ~/.config/abstractions.

set -euo pipefail

INSTALLSH_DIR="${INSTALLSH_DIR:-$HOME/.config/installSH}"
APPS_APPIMAGES="$INSTALLSH_DIR/apps_AppImages.sh"
APPS_ZED="$INSTALLSH_DIR/apps_zed.sh"
APPS_ZEN="$INSTALLSH_DIR/apps_zen.sh"
FLAGS_DIR="${INSTALLSH_FLAGS_DIR:-$INSTALLSH_DIR/flags}"

# Shared flag/token helpers. These are also used by the app checkers.
if [[ -r "$INSTALLSH_DIR/lib/state.sh" ]]; then
    # shellcheck source=lib/state.sh
    source "$INSTALLSH_DIR/lib/state.sh"

    # Resolve the token once and export it so the child checkers inherit it.
    # This keeps login checks working without shell-exported credentials.
    GITHUB_TOKEN="$(installsh_github_token 2>/dev/null || true)"
    export GITHUB_TOKEN
fi

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/update-check"
STATUS_FILE="$CACHE_DIR/status.env"
REPORT_TSV="$CACHE_DIR/report.tsv"
REPORT_TXT="$CACHE_DIR/report.txt"
LOG_FILE="$CACHE_DIR/update-check.log"
LOCK_FILE="$CACHE_DIR/lock"
POPUP_SCRIPT="$HOME/.local/bin/update-check-popup.sh"
UPDATER_SCRIPT="$CACHE_DIR/update-now.sh"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/update-check/icons"

CACHE_SECONDS="${UPDATE_CHECK_CACHE_SECONDS:-300}"
APPIMAGE_TIMEOUT="${UPDATE_CHECK_APPIMAGE_TIMEOUT:-90}"
ZED_TIMEOUT="${UPDATE_CHECK_ZED_TIMEOUT:-25}"
ZEN_TIMEOUT="${UPDATE_CHECK_ZEN_TIMEOUT:-25}"
NOTIFY_EXPIRE_MS="${UPDATE_CHECK_NOTIFY_EXPIRE_MS:-15000}"

MODE="check"
NO_NOTIFY=0
FORCE=0
SHORT=0
CACHE_HIT=0

STATUS=""
TITLE=""
BODY=""
UPDATES=0
ERRORS=0
MANAGED=0
TIMED_OUT=0
PRECHECK_STATUS=""
PRECHECK_REASON=""
PRECHECK_RESET=""
PREFLIGHT_FAILED=0
NOTIFY_ICON="dialog-information"
NOTIFY_URGENCY="normal"

UPDATE_LINES=()
ERROR_LINES=()
REPORT_ROWS=()
REPORT_TEXT=()
FLAG_FILES=()
AI_FLAGS=()
ZED_FLAGS=()
ZEN_FLAGS=()
OTHER_FLAGS=()
AI_UPDATE_INDICES=()
ZED_NEEDS_UPDATE=0
ZEN_NEEDS_UPDATE=0

usage() {
    cat <<'EOF'
Usage: update-check.sh [OPTIONS]

Options:
  --force            Ignore the short cache window (used by autostart)
  --list             Print the human-readable report
  --json             Print machine-readable JSON
  --status           Print ~/.cache/update-check/status.env
  --status --short   Print a one-line status summary
  --update-list      Print all apps registered with update-check
  --apply            Interactively apply available updates
  --no-notify        Write report/status/log only
  -h, --help         Show this help

Default mode checks managed installations, sends one notification, and exits.

GitHub token (optional, avoids anonymous rate limits):
  export GITHUB_TOKEN=... or GH_TOKEN=...
  or save it in ~/.config/installSH/github-token
EOF
}

log() {
    printf '[%s] %s\n' "$(date -Is)" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

kv_get() {
    local file="$1"
    local key="$2"
    local line

    [[ -r "$file" ]] || return 1
    line="$(grep -m1 -E "^${key}=" -- "$file" 2>/dev/null || true)"
    [[ -n "$line" ]] || return 1
    printf '%s\n' "${line#*=}"
}

flag_files() {
    [[ -d "$FLAGS_DIR" ]] || return 0
    find "$FLAGS_DIR" -maxdepth 1 -type f -name '*.env' -printf '%p\n' 2>/dev/null | sort
}

add_row() {
    local kind="$1"
    local id="$2"
    local name="$3"
    local current="$4"
    local latest="$5"
    local state="$6"
    local detail="$7"

    REPORT_ROWS+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' \
        "$kind" "$id" "$name" "$current" "$latest" "$state" "$detail")")
}

add_text() {
    REPORT_TEXT+=("$1")
}

record_update() {
    UPDATE_LINES+=("$1")
    UPDATES=$((UPDATES + 1))
    add_text "[update] $1"
}

record_error() {
    ERROR_LINES+=("$1")
    ERRORS=$((ERRORS + 1))
    add_text "[error]  $1"
}

# Summarise the previous successful run, used when the current run is blocked
# by the GitHub rate limit. Reads the status file before it is overwritten.
last_successful_summary() {
    local file="$STATUS_FILE" s updates checked

    [[ -r "$file" ]] || return 1

    s="$(kv_get "$file" status || true)"
    case "$s" in
        updates|ok|partial) ;;
        *) return 1 ;;
    esac

    updates="$(kv_get "$file" updates || echo 0)"
    checked="$(kv_get "$file" checked_at || true)"

    case "$s" in
        updates) printf '%s update(s) available' "${updates:-0}" ;;
        partial) printf 'check completed with errors' ;;
        ok)      printf 'no updates available' ;;
    esac

    if [[ -n "$checked" ]]; then
        printf ' (%s)' "$checked"
    fi
    return 0
}

build_messages() {
    local line body last

    case "$STATUS" in
        updates)
            TITLE="Updates available ($UPDATES)"
            body=""
            for line in "${UPDATE_LINES[@]:0:6}"; do
                body+="• $line"$'\n'
            done
            if (( ${#UPDATE_LINES[@]} > 6 )); then
                body+="… and $(( ${#UPDATE_LINES[@]} - 6 )) more"$'\n'
            fi
            body+="Run: update-check.sh --apply"
            BODY="$body"
            ;;
        ok)
            TITLE="No updates available"
            BODY="All $MANAGED managed app(s) are current."
            ;;
        partial)
            TITLE="Update check completed with errors"
            body="$UPDATES update(s) available; $ERRORS check(s) failed."
            body+=$'\n'
            for line in "${UPDATE_LINES[@]:0:4}"; do
                body+="• $line"$'\n'
            done
            body+="Failed:"$'\n'
            for line in "${ERROR_LINES[@]:0:3}"; do
                body+="• $line"$'\n'
            done
            body+="See: $LOG_FILE"
            BODY="$body"
            ;;
        offline)
            TITLE="Unable to check for updates"
            BODY="GitHub is unreachable. Check your connection."$'\n'"Log: $LOG_FILE"
            ;;
        rate-limited)
            TITLE="Update check rate-limited"
            BODY="GitHub API limit reached."
            if [[ "$PRECHECK_RESET" =~ ^[0-9]+$ ]]; then
                BODY+=" Quota resets at $(date -d "@$PRECHECK_RESET" '+%H:%M')."
            fi
            BODY+=$'\n'"Try again later or save a token in $HOME/.config/installSH/github-token."
            last="$(last_successful_summary || true)"
            if [[ -n "$last" ]]; then
                BODY+=$'\n'"Last successful check: $last"
            fi
            ;;
        timeout)
            TITLE="Update check timed out"
            BODY="A check did not finish in time."$'\n'"See: $LOG_FILE"
            ;;
        skipped)
            TITLE="Update check skipped"
            BODY="Another update check is already running."
            ;;
        no-flags)
            TITLE="Update check skipped"
            BODY="No managed apps found in $FLAGS_DIR."$'\n'"Install an app to register it."
            ;;
        error|*)
            TITLE="Update check failed"
            BODY="See: $LOG_FILE"
            ;;
    esac
}

write_status_files() {
    local now_epoch now_iso flat

    now_epoch="$(date +%s)"
    now_iso="$(date -Is)"
    flat="$(printf '%s' "$BODY" | tr '\n' ' ')"

    {
        printf 'status=%s\n' "$STATUS"
        printf 'checked_at=%s\n' "$now_iso"
        printf 'checked_at_epoch=%s\n' "$now_epoch"
        printf 'updates=%s\n' "$UPDATES"
        printf 'errors=%s\n' "$ERRORS"
        printf 'managed=%s\n' "$MANAGED"
        printf 'title=%s\n' "$TITLE"
        printf 'message=%s\n' "$flat"
    } >"$STATUS_FILE.tmp" 2>/dev/null \
        && mv -f -- "$STATUS_FILE.tmp" "$STATUS_FILE" 2>/dev/null || true

    {
        printf 'kind\tid\tname\tcurrent\tlatest\tstate\tdetail\n'
        if (( ${#REPORT_ROWS[@]} > 0 )); then
            printf '%s\n' "${REPORT_ROWS[@]}"
        fi
    } >"$REPORT_TSV.tmp" 2>/dev/null \
        && mv -f -- "$REPORT_TSV.tmp" "$REPORT_TSV" 2>/dev/null || true

    {
        printf 'System Update Check\n'
        printf '===================\n\n'
        printf '%s\n' "$TITLE"
        printf '%s\n\n' "$BODY"
        printf 'Status : %s\n' "$STATUS"
        printf 'Checked: %s\n' "$now_iso"
        printf 'Managed: %s  Updates: %s  Errors: %s\n' "$MANAGED" "$UPDATES" "$ERRORS"
        printf '\n'
        if (( ${#REPORT_TEXT[@]} > 0 )); then
            printf '%s\n' "${REPORT_TEXT[@]}"
        fi
        printf '\nLog: %s\n' "$LOG_FILE"
    } >"$REPORT_TXT.tmp" 2>/dev/null \
        && mv -f -- "$REPORT_TXT.tmp" "$REPORT_TXT" 2>/dev/null || true
}

print_report() {
    cat "$REPORT_TXT" 2>/dev/null || true
}

print_json() {
    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg status "$STATUS" \
            --arg title "$TITLE" \
            --arg message "$BODY" \
            --argjson updates "$UPDATES" \
            --argjson errors "$ERRORS" \
            --argjson managed "$MANAGED" \
            '{status:$status,title:$title,message:$message,updates:$updates,errors:$errors,managed:$managed}'
    else
        printf '{"status":"%s","updates":%d,"errors":%d,"managed":%d}\n' \
            "$STATUS" "$UPDATES" "$ERRORS" "$MANAGED"
    fi
}

# Print the result for runs that end before the normal check/apply flow.
# Default check mode still writes status and notifies via finalize.
emit_early_output() {
    case "$MODE" in
        list)
            write_status_files
            print_report
            ;;
        json)
            write_status_files
            print_json
            ;;
        apply)
            write_status_files
            print_report
            ;;
        check)
            if [[ -t 1 ]]; then
                write_status_files
                print_report
            fi
            ;;
    esac
}

build_updater_script() {
    local idx

    {
        printf '#!/usr/bin/env bash\n'
        printf 'set +e\n'
        printf 'echo "Applying updates..."\n'
        printf 'echo\n'

        for idx in "${AI_UPDATE_INDICES[@]}"; do
            printf 'printf "\\n=== Updating AppImage index %s ===\\n"\n' "$idx"
            printf '%q --update %q\n' "$APPS_APPIMAGES" "$idx"
        done

        if (( ZED_NEEDS_UPDATE == 1 )); then
            printf 'printf "\\n=== Updating Zed ===\\n"\n'
            printf '%q --update\n' "$APPS_ZED"
        fi

        if (( ZEN_NEEDS_UPDATE == 1 )); then
            printf 'printf "\\n=== Updating Zen Browser ===\\n"\n'
            printf 'if command -v sudo >/dev/null 2>&1; then sudo %q --update; else echo "sudo not found; run manually: sudo %s --update"; fi\n' \
                "$APPS_ZEN" "$APPS_ZEN"
        fi

        printf 'echo\n'
        printf 'echo "Done. Press Enter to close."\n'
        printf 'read -r _ || true\n'
    } >"$UPDATER_SCRIPT" 2>/dev/null

    chmod +x "$UPDATER_SCRIPT" 2>/dev/null || true
}

launch_update_terminal() {
    local cmd

    [[ -x "$UPDATER_SCRIPT" ]] || return 0

    log "launching update terminal"

    # shellcheck disable=SC1090
    source "$HOME/.config/abstractions/wm.sh" 2>/dev/null || true

    if ! command -v WM_exec_floating >/dev/null 2>&1; then
        log "WM API unavailable; cannot open update terminal"
        return 0
    fi

    cmd="$(printf '%q ' env \
        "UPDATE_CHECK_CACHE_DIR=$CACHE_DIR" \
        foot --app-id=UpdateCheckPopup --title=UpdateCheckPopup \
        -w 900x420 -e bash "$UPDATER_SCRIPT")"

    WM_exec_floating "$cmd" true 0.50 0.40 >>"$LOG_FILE" 2>&1 \
        || log "WM_exec_floating failed"
}

print_managed_apps() {
    local -a files=()
    local f id kind name version idx

    mapfile -t files < <(flag_files)

    if (( ${#files[@]} == 0 )); then
        printf 'No managed apps found in %s.\n' "$FLAGS_DIR"
        return 0
    fi

    printf '%-24s %-10s %-24s %-16s %s\n' \
        "ID" "KIND" "NAME" "INSTALLED" "SOURCE INDEX"
    printf '%s\n' "--------------------------------------------------------------------------------"

    for f in "${files[@]}"; do
        id="$(kv_get "$f" id || true)"
        kind="$(kv_get "$f" kind || true)"
        name="$(kv_get "$f" name || true)"
        version="$(kv_get "$f" installed_version || true)"
        idx="$(kv_get "$f" source_index || true)"

        [[ -n "$id" ]] || id="$(basename "$f" .env)"
        [[ -n "$kind" ]] || kind="unknown"
        [[ -n "$name" ]] || name="$id"
        [[ -n "$version" ]] || version="-"
        [[ -n "$idx" ]] || idx="-"

        printf '%-24s %-10s %-24s %-16s %s\n' \
            "$id" "$kind" "$name" "$version" "$idx"
    done
}
send_notification() {
    local i action rc
    local -a notify_args=()

    command -v notify-send >/dev/null 2>&1 || {
        log "notify-send not found"
        return 1
    }

    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
    fi

    # Wait briefly for the notification daemon to come up after login.
    if command -v busctl >/dev/null 2>&1; then
        for ((i = 0; i < 20; i++)); do
            if busctl --user status org.freedesktop.Notifications >/dev/null 2>&1; then
                break
            fi
            sleep 0.5
        done
    fi

    notify_args=(
        --app-name="System Update Check"
        --hint=string:desktop-entry:system-update-check
        --icon="$NOTIFY_ICON"
        --urgency="$NOTIFY_URGENCY"
        --expire-time="$NOTIFY_EXPIRE_MS"
    )

    # Offer an action button only when updates are available and an updater
    # script has been prepared.
    if [[ "$STATUS" == "updates" && -x "$UPDATER_SCRIPT" ]]; then
        notify_args+=(-A "update=Update" -A "ok=OK")
    fi

    rc=0
    action="$(timeout 20 notify-send -w "${notify_args[@]}" "$TITLE" "$BODY" 2>>"$LOG_FILE")" || rc=$?

    if (( rc != 0 )); then
        log "notify-send failed (rc=$rc)"
        return 1
    fi

    if [[ "$action" == "update" ]]; then
        launch_update_terminal
    fi

    return 0
}

show_popup_fallback() {
    local cmd

    log "notification failed; trying foot popup fallback"

    [[ -x "$POPUP_SCRIPT" ]] || {
        log "popup script missing: $POPUP_SCRIPT"
        return 0
    }
    command -v foot >/dev/null 2>&1 || {
        log "foot not found; cannot open popup"
        return 0
    }

    # shellcheck disable=SC1090
    source "$HOME/.config/abstractions/wm.sh" 2>/dev/null || true

    if ! command -v WM_exec_floating >/dev/null 2>&1; then
        log "WM API unavailable; cannot open popup"
        return 0
    fi

    cmd="$(printf '%q ' env \
        "UPDATE_CHECK_CACHE_DIR=$CACHE_DIR" \
        foot --app-id=UpdateCheckPopup --title=UpdateCheckPopup \
        -w 900x420 -e bash "$POPUP_SCRIPT")"

    WM_exec_floating "$cmd" true 0.50 0.40 >>"$LOG_FILE" 2>&1 \
        || log "WM_exec_floating failed"
}

finalize() {
    local rc=$?

    set +e

    # A cached run must not rewrite checked_at (that would extend the cache
    # window forever) and must not notify again.
    if (( CACHE_HIT == 1 )); then
        exit "$rc"
    fi

    [[ -n "$STATUS" ]] || STATUS="error"
    [[ -n "$TITLE" ]] || build_messages

    if [[ "$STATUS" == "updates" ]]; then
        build_updater_script
    fi

    write_status_files

    if (( NO_NOTIFY == 0 )); then
        if ! send_notification; then
            show_popup_fallback
        fi
    fi

    exit "$rc"
}

send_completion_notification() {
    local ok="$1"
    local fail="$2"
    local icon

    if (( fail == 0 )); then
        icon="$(icon_path ok)"
    else
        icon="$(icon_path warning)"
    fi

    timeout 5 notify-send \
        --app-name="System Update Check" \
        --hint=string:desktop-entry:system-update-check \
        --icon="$icon" \
        --urgency=normal \
        --expire-time="$NOTIFY_EXPIRE_MS" \
        "Updates applied" \
        "$ok succeeded, $fail failed." >>"$LOG_FILE" 2>&1 || true
}

mark_all_failed() {
    local reason="$1"
    local f kind id name

    # Only network-backed flags; OTHER_FLAGS have already been recorded.
    for f in "${AI_FLAGS[@]}" "${ZED_FLAGS[@]}" "${ZEN_FLAGS[@]}"; do
        kind="$(kv_get "$f" kind || true)"
        id="$(kv_get "$f" id || true)"
        name="$(kv_get "$f" name || true)"
        [[ -n "$id" ]] || id="$(basename "$f" .env)"
        [[ -n "$name" ]] || name="$id"
        record_error "$name: $reason"
        add_row "${kind:-unknown}" "$id" "$name" "-" "-" "error" "$reason"
    done
}

preflight_network() {
    local response remaining reset
    local -a auth=()

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    response="$(curl -fsS --connect-timeout 5 --max-time 10 \
        "${auth[@]}" \
        -H "Accept: application/vnd.github+json" \
        https://api.github.com/rate_limit 2>/dev/null || true)"

    if [[ -z "$response" ]]; then
        PRECHECK_STATUS="offline"
        PRECHECK_REASON="network unavailable"
        return 1
    fi

    remaining="$(jq -r '.rate.remaining // empty' <<<"$response" 2>/dev/null || true)"
    if [[ "$remaining" == "0" ]] \
        || grep -qi 'API rate limit exceeded' <<<"$response"; then
        PRECHECK_STATUS="rate-limited"
        PRECHECK_REASON="GitHub rate limit reached"
        reset="$(jq -r '.rate.reset // empty' <<<"$response" 2>/dev/null || true)"
        if [[ "$reset" =~ ^[0-9]+$ ]]; then
            PRECHECK_RESET="$reset"
        fi
        return 1
    fi

    return 0
}

run_appimage_checks() {
    local out rc f id name idx current latest state detail reason
    local -A ai_name=() ai_current=() ai_latest=() ai_state=() ai_detail=()

    (( ${#AI_FLAGS[@]} > 0 )) || return 0

    if [[ ! -x "$APPS_APPIMAGES" ]]; then
        reason="apps_AppImages.sh not executable"
        for f in "${AI_FLAGS[@]}"; do
            id="$(kv_get "$f" id || true)"
            name="$(kv_get "$f" name || true)"
            [[ -n "$id" ]] || id="$(basename "$f" .env)"
            [[ -n "$name" ]] || name="$id"
            record_error "$name: $reason"
            add_row appimage "$id" "$name" "-" "-" "error" "$reason"
        done
        return 0
    fi

    out="$CACHE_DIR/appimage-check.tsv"

    set +e
    timeout "$APPIMAGE_TIMEOUT" "$APPS_APPIMAGES" --check all \
        >"$out" 2>>"$LOG_FILE"
    rc=$?
    set -e

    if (( rc != 0 )); then
        if (( rc == 124 )); then
            TIMED_OUT=1
            reason="checker timed out"
        else
            reason="checker failed (rc=$rc)"
        fi
        for f in "${AI_FLAGS[@]}"; do
            id="$(kv_get "$f" id || true)"
            name="$(kv_get "$f" name || true)"
            [[ -n "$id" ]] || id="$(basename "$f" .env)"
            [[ -n "$name" ]] || name="$id"
            record_error "$name: $reason"
            add_row appimage "$id" "$name" "-" "-" "error" "$reason"
        done
        return 0
    fi

    while IFS=$'\t' read -r idx name current latest state detail; do
        if [[ "$idx" == "index" ]]; then
            continue
        fi
        [[ -n "$idx" ]] || continue
        ai_name["$idx"]="$name"
        ai_current["$idx"]="$current"
        ai_latest["$idx"]="$latest"
        ai_state["$idx"]="$state"
        ai_detail["$idx"]="${detail:-}"
    done <"$out"

    for f in "${AI_FLAGS[@]}"; do
        id="$(kv_get "$f" id || true)"
        name="$(kv_get "$f" name || true)"
        idx="$(kv_get "$f" source_index || true)"
        [[ -n "$id" ]] || id="$(basename "$f" .env)"
        [[ -n "$name" ]] || name="$id"

        state="${ai_state[$idx]:-}"
        current="${ai_current[$idx]:-unknown}"
        latest="${ai_latest[$idx]:-unknown}"
        detail="${ai_detail[$idx]:-}"

        if [[ -z "$state" ]]; then
            record_error "$name: no check result"
            add_row appimage "$id" "$name" "$current" "$latest" "error" "no check result"
            continue
        fi

        case "$state" in
            update)
                record_update "$name $current → $latest"
                add_row appimage "$id" "$name" "$current" "$latest" "update" "$detail"
                AI_UPDATE_INDICES+=("$idx")
                ;;
            current|newer)
                add_row appimage "$id" "$name" "$current" "$latest" "$state" "$detail"
                ;;
            not-installed)
                record_error "$name: installation missing"
                add_row appimage "$id" "$name" "$current" "$latest" "error" "installation missing"
                ;;
            *)
                record_error "$name: ${detail:-check failed}"
                add_row appimage "$id" "$name" "$current" "$latest" "error" "${detail:-check failed}"
                ;;
        esac
    done
}

run_zed_checks() {
    local out rc f id name tag current latest state detail reason

    (( ${#ZED_FLAGS[@]} > 0 )) || return 0

    if [[ ! -x "$APPS_ZED" ]]; then
        reason="apps_zed.sh not executable"
        for f in "${ZED_FLAGS[@]}"; do
            id="$(kv_get "$f" id || true)"
            name="$(kv_get "$f" name || true)"
            [[ -n "$id" ]] || id="$(basename "$f" .env)"
            [[ -n "$name" ]] || name="$id"
            record_error "$name: $reason"
            add_row zed "$id" "$name" "-" "-" "error" "$reason"
        done
        return 0
    fi

    out="$CACHE_DIR/zed-check.tsv"
    current=""
    latest=""
    state=""
    detail=""

    set +e
    timeout "$ZED_TIMEOUT" "$APPS_ZED" --check >"$out" 2>>"$LOG_FILE"
    rc=$?
    set -e

    if (( rc != 0 )); then
        if (( rc == 124 )); then
            TIMED_OUT=1
            reason="checker timed out"
        else
            reason="checker failed (rc=$rc)"
        fi
        for f in "${ZED_FLAGS[@]}"; do
            id="$(kv_get "$f" id || true)"
            name="$(kv_get "$f" name || true)"
            [[ -n "$id" ]] || id="$(basename "$f" .env)"
            [[ -n "$name" ]] || name="$id"
            record_error "$name: $reason"
            add_row zed "$id" "$name" "-" "-" "error" "$reason"
        done
        return 0
    fi

    IFS=$'\t' read -r tag current latest state detail < <(head -n1 "$out" 2>/dev/null || true)

    if [[ -z "$state" ]]; then
        for f in "${ZED_FLAGS[@]}"; do
            id="$(kv_get "$f" id || true)"
            name="$(kv_get "$f" name || true)"
            [[ -n "$id" ]] || id="$(basename "$f" .env)"
            [[ -n "$name" ]] || name="$id"
            record_error "$name: no check result"
            add_row zed "$id" "$name" "-" "-" "error" "no check result"
        done
        return 0
    fi

    for f in "${ZED_FLAGS[@]}"; do
        id="$(kv_get "$f" id || true)"
        name="$(kv_get "$f" name || true)"
        [[ -n "$id" ]] || id="$(basename "$f" .env)"
        [[ -n "$name" ]] || name="$id"

        case "$state" in
            update)
                record_update "$name $current → $latest"
                add_row zed "$id" "$name" "$current" "$latest" "update" "${detail:-}"
                ZED_NEEDS_UPDATE=1
                ;;
            current|newer)
                add_row zed "$id" "$name" "$current" "$latest" "$state" "${detail:-}"
                ;;
            *)
                record_error "$name: ${detail:-check failed}"
                add_row zed "$id" "$name" "$current" "$latest" "error" "${detail:-check failed}"
                ;;
        esac
    done
}

run_zen_checks() {
    local out rc f id name current latest state detail reason

    (( ${#ZEN_FLAGS[@]} > 0 )) || return 0

    if [[ ! -x "$APPS_ZEN" ]]; then
        reason="apps_zen.sh not executable"
        for f in "${ZEN_FLAGS[@]}"; do
            id="$(kv_get "$f" id || true)"
            name="$(kv_get "$f" name || true)"
            [[ -n "$id" ]] || id="$(basename "$f" .env)"
            [[ -n "$name" ]] || name="$id"
            record_error "$name: $reason"
            add_row zen "$id" "$name" "-" "-" "error" "$reason"
        done
        return 0
    fi

    out="$CACHE_DIR/zen-check.tsv"

    set +e
    timeout "$ZEN_TIMEOUT" "$APPS_ZEN" --check >"$out" 2>>"$LOG_FILE"
    rc=$?
    set -e

    if (( rc != 0 )); then
        if (( rc == 124 )); then
            TIMED_OUT=1
            reason="checker timed out"
        else
            reason="checker failed (rc=$rc)"
        fi
        for f in "${ZEN_FLAGS[@]}"; do
            id="$(kv_get "$f" id || true)"
            name="$(kv_get "$f" name || true)"
            [[ -n "$id" ]] || id="$(basename "$f" .env)"
            [[ -n "$name" ]] || name="$id"
            record_error "$name: $reason"
            add_row zen "$id" "$name" "-" "-" "error" "$reason"
        done
        return 0
    fi

    IFS=$'\t' read -r tag current latest state detail < <(grep -m1 -E '^zen[[:space:]]' "$out" 2>/dev/null || true)

    if [[ -z "$state" ]]; then
        for f in "${ZEN_FLAGS[@]}"; do
            id="$(kv_get "$f" id || true)"
            name="$(kv_get "$f" name || true)"
            [[ -n "$id" ]] || id="$(basename "$f" .env)"
            [[ -n "$name" ]] || name="$id"
            record_error "$name: no check result"
            add_row zen "$id" "$name" "-" "-" "error" "no check result"
        done
        return 0
    fi

    for f in "${ZEN_FLAGS[@]}"; do
        id="$(kv_get "$f" id || true)"
        name="$(kv_get "$f" name || true)"
        [[ -n "$id" ]] || id="$(basename "$f" .env)"
        [[ -n "$name" ]] || name="$id"

        case "$state" in
            update)
                record_update "$name $current → $latest"
                add_row zen "$id" "$name" "$current" "$latest" "update" "${detail:-}"
                ZEN_NEEDS_UPDATE=1
                ;;
            current|newer)
                add_row zen "$id" "$name" "$current" "$latest" "$state" "${detail:-}"
                ;;
            not-installed)
                record_error "$name: installation missing"
                add_row zen "$id" "$name" "$current" "$latest" "error" "installation missing"
                ;;
            *)
                record_error "$name: ${detail:-check failed}"
                add_row zen "$id" "$name" "$current" "$latest" "error" "${detail:-check failed}"
                ;;
        esac
    done
}

classify() {
    if [[ -n "$PRECHECK_STATUS" ]]; then
        STATUS="$PRECHECK_STATUS"
        return 0
    fi

    if (( TIMED_OUT )); then
        STATUS="timeout"
    elif (( UPDATES > 0 && ERRORS > 0 )); then
        STATUS="partial"
    elif (( ERRORS > 0 && ERRORS >= MANAGED )); then
        STATUS="error"
    elif (( ERRORS > 0 )); then
        STATUS="partial"
    elif (( UPDATES > 0 )); then
        STATUS="updates"
    else
        STATUS="ok"
    fi
}

theme_icon_name() {
    case "$1" in
        updates) printf 'software-update-available' ;;
        ok)      printf 'emblem-ok-symbolic' ;;
        warning) printf 'dialog-warning' ;;
        error)   printf 'dialog-error' ;;
        offline) printf 'network-error' ;;
        info|*)  printf 'dialog-information' ;;
    esac
}

# Prefer the bundled 64px SVGs. Passing an absolute path bypasses icon-theme
# lookup, which otherwise upscales Papirus-Dark's 16-24px status icons to
# swaync's 64px notification size and makes them look blurry.
icon_path() {
    local key="$1"
    local path="$ICON_DIR/$key.svg"

    if [[ -r "$path" ]]; then
        printf '%s' "$path"
    else
        theme_icon_name "$key"
    fi
}

set_icon_and_urgency() {
    case "$STATUS" in
        updates)
            NOTIFY_ICON="$(icon_path updates)"
            NOTIFY_URGENCY="normal"
            ;;
        ok)
            NOTIFY_ICON="$(icon_path ok)"
            NOTIFY_URGENCY="low"
            ;;
        partial)
            NOTIFY_ICON="$(icon_path warning)"
            NOTIFY_URGENCY="normal"
            ;;
        offline)
            NOTIFY_ICON="$(icon_path offline)"
            NOTIFY_URGENCY="normal"
            ;;
        rate-limited|skipped|no-flags)
            NOTIFY_ICON="$(icon_path info)"
            NOTIFY_URGENCY="low"
            ;;
        timeout|error|*)
            NOTIFY_ICON="$(icon_path error)"
            NOTIFY_URGENCY="normal"
            ;;
    esac
}

# ------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------

while (( $# > 0 )); do
    case "$1" in
        --force)
            FORCE=1
            shift
            ;;
        --list)
            MODE="list"
            NO_NOTIFY=1
            shift
            ;;
        --json)
            MODE="json"
            NO_NOTIFY=1
            shift
            ;;
        --status)
            MODE="status"
            shift
            ;;
        --update-list)
            MODE="update-list"
            NO_NOTIFY=1
            shift
            ;;
        --short)
            SHORT=1
            shift
            ;;
        --apply)
            MODE="apply"
            NO_NOTIFY=1
            shift
            ;;
        --no-notify)
            NO_NOTIFY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'update-check: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# Status mode is deliberately side-effect free.
if [[ "$MODE" == "status" ]]; then
    if [[ ! -r "$STATUS_FILE" ]]; then
        printf 'update-check: no status yet (%s)\n' "$STATUS_FILE" >&2
        exit 1
    fi
    if (( SHORT == 1 )); then
        printf 'status=%s updates=%s errors=%s managed=%s\n' \
            "$(kv_get "$STATUS_FILE" status || echo unknown)" \
            "$(kv_get "$STATUS_FILE" updates || echo 0)" \
            "$(kv_get "$STATUS_FILE" errors || echo 0)" \
            "$(kv_get "$STATUS_FILE" managed || echo 0)"
    else
        cat "$STATUS_FILE"
    fi
    exit 0
fi

if [[ "$MODE" == "update-list" ]]; then
    print_managed_apps
    exit 0
fi
trap finalize EXIT
trap 'exit 143' TERM INT

log "update-check: start (mode=$MODE force=$FORCE)"
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    log "github token: configured"
else
    log "github token: not configured (anonymous API)"
fi

# ------------------------------------------------------------
# One instance at a time
# ------------------------------------------------------------

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    STATUS="skipped"
    set_icon_and_urgency
    build_messages
    log "another update check is already running"
    emit_early_output
    exit 0
fi

# ------------------------------------------------------------
# Short cache window for repeated manual runs
# ------------------------------------------------------------

if (( FORCE == 0 )) && [[ "$MODE" == "check" ]]; then
    cached_status="$(kv_get "$STATUS_FILE" status || true)"
    cached_epoch="$(kv_get "$STATUS_FILE" checked_at_epoch || true)"

    if [[ "$cached_status" =~ ^(updates|ok|partial|error|offline|rate-limited|timeout)$ ]] \
        && [[ "$cached_epoch" =~ ^[0-9]+$ ]] \
        && (( $(date +%s) - cached_epoch < CACHE_SECONDS )); then
        STATUS="$cached_status"
        TITLE="$(kv_get "$STATUS_FILE" title || true)"
        BODY="$(kv_get "$STATUS_FILE" message || true)"
        UPDATES="$(kv_get "$STATUS_FILE" updates || echo 0)"
        ERRORS="$(kv_get "$STATUS_FILE" errors || echo 0)"
        MANAGED="$(kv_get "$STATUS_FILE" managed || echo 0)"
        [[ -n "$TITLE" ]] || build_messages
        CACHE_HIT=1
        log "using cached status from ${cached_epoch}"
        if [[ "$MODE" == "check" && -t 1 ]]; then
            print_report
        fi
        exit 0
    fi
fi

# ------------------------------------------------------------
# Collect installation flags
# ------------------------------------------------------------

mapfile -t FLAG_FILES < <(flag_files)
MANAGED=${#FLAG_FILES[@]}

if (( MANAGED == 0 )); then
    STATUS="no-flags"
    set_icon_and_urgency
    build_messages
    log "no installation flags found in $FLAGS_DIR"
    emit_early_output
    exit 0
fi

for f in "${FLAG_FILES[@]}"; do
    kind="$(kv_get "$f" kind || true)"
    case "$kind" in
        appimage) AI_FLAGS+=("$f") ;;
        zed)      ZED_FLAGS+=("$f") ;;
        zen)      ZEN_FLAGS+=("$f") ;;
        *)        OTHER_FLAGS+=("$f") ;;
    esac
done

for f in "${OTHER_FLAGS[@]}"; do
    id="$(kv_get "$f" id || true)"
    name="$(kv_get "$f" name || true)"
    kind="$(kv_get "$f" kind || true)"
    [[ -n "$id" ]] || id="$(basename "$f" .env)"
    [[ -n "$name" ]] || name="$id"
    record_error "$name: unsupported flag kind '${kind:-unknown}'"
    add_row "${kind:-unknown}" "$id" "$name" "-" "-" "error" "unsupported flag kind"
done

# ------------------------------------------------------------
# Network preflight
# ------------------------------------------------------------

if (( ${#AI_FLAGS[@]} > 0 || ${#ZED_FLAGS[@]} > 0 || ${#ZEN_FLAGS[@]} > 0 )); then
    if ! preflight_network; then
        mark_all_failed "${PRECHECK_REASON:-network unavailable}"
        classify
        set_icon_and_urgency
        build_messages
        PREFLIGHT_FAILED=1
        log "preflight failed: $STATUS"
    fi
fi

# ------------------------------------------------------------
# Run checks
# ------------------------------------------------------------

if (( PREFLIGHT_FAILED == 0 )); then
    run_appimage_checks
    run_zed_checks
    run_zen_checks

    classify
    set_icon_and_urgency
    build_messages

    log "result: status=$STATUS updates=$UPDATES errors=$ERRORS managed=$MANAGED"
fi

# ------------------------------------------------------------
# Mode output
# ------------------------------------------------------------

case "$MODE" in
    list)
        write_status_files
        print_report
        exit 0
        ;;
    json)
        write_status_files
        print_json
        exit 0
        ;;
    apply)
        write_status_files
        print_report
        if (( UPDATES == 0 )); then
            printf '\nNothing to update.\n'
            exit 0
        fi

        printf '\n%d update(s) available.\n' "$UPDATES"
        answer=""
        read -r -p "Apply updates now? [y/N] " answer || true
        case "$answer" in
            y|Y|yes|YES) ;;
            *)
                printf 'Cancelled.\n'
                exit 0
                ;;
        esac

        ok=0
        fail=0

        for idx in "${AI_UPDATE_INDICES[@]}"; do
            printf '\n=== Updating AppImage index %s ===\n' "$idx"
            if "$APPS_APPIMAGES" --update "$idx"; then
                ok=$((ok + 1))
            else
                fail=$((fail + 1))
            fi
        done

        if (( ZED_NEEDS_UPDATE == 1 )); then
            printf '\n=== Updating Zed ===\n'
            if "$APPS_ZED" --update; then
                ok=$((ok + 1))
            else
                fail=$((fail + 1))
            fi
        fi

        if (( ZEN_NEEDS_UPDATE == 1 )); then
            printf '\n=== Updating Zen Browser ===\n'
            if ! command -v sudo >/dev/null 2>&1; then
                printf 'sudo is not available. Run manually: sudo %s --update\n' "$APPS_ZEN"
                fail=$((fail + 1))
            elif sudo "$APPS_ZEN" --update; then
                ok=$((ok + 1))
            else
                fail=$((fail + 1))
            fi
        fi

        printf '\nApplied: %d, failed: %d\n' "$ok" "$fail"
        send_completion_notification "$ok" "$fail"
        exit 0
        ;;
    check)
        if [[ -t 1 ]]; then
            write_status_files
            print_report
        fi
        exit 0
        ;;
esac
