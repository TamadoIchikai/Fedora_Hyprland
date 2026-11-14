#!/usr/bin/env bash
#
# cache_To_SSD.sh - move a folder from $HOME (HDD) to the SSD and leave a
# symlink at the original path. Keeps a registry so moves can be listed,
# reverted by number, and re-applied after a reinstall / on a new machine.
#
#   ./cache_To_SSD.sh --add|-a <PATH>
#   ./cache_To_SSD.sh --list|-ls
#   ./cache_To_SSD.sh --list-not-restore|-lsNrst
#   ./cache_To_SSD.sh --restore|-rst
#   ./cache_To_SSD.sh --revert|-r <INDEX>
#   ./cache_To_SSD.sh --help|-h
#
# Target:   ${CACHE2SSD_BASE:-/var/home}/<user>/<name>
# Registry: ~/.config/installSH/flags/cache_to_ssd.tsv  (tracked by chezmoi)
#           <orig rel. to $HOME><TAB><target rel. to SSD dir><TAB><added_at>
#           Relative paths keep it portable (new machine / other username).
#           Old absolute lines are still read and rewritten on the next save.
#           Not .env on purpose: update-check.sh scans flags/*.env.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

TMP_SUFFIX=".cache2ssd-tmp-"

usage() {
    cat <<EOF
Usage: $0 --add|-a <PATH>               move <PATH> to the SSD and symlink it back
                                         (skipped if <PATH> does not exist)
       $0 --list|-ls                    list saved folders (numbered)
       $0 --list-not-restore|-lsNrst    list saved folders that are not restored
                                         because their path does not exist
       $0 --restore|-rst                re-apply every saved folder (after a
                                         reinstall / on a new machine)
       $0 --revert|-r <INDEX>           move entry <INDEX> back and remove the symlink
       $0 --help|-h                     show this help

Folders go to ${CACHE2SSD_BASE:-/var/home}/$(id -un)/. Run as your own user (not root).
EOF
}

# ---------------------------------------------------------------- setup ----

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    die "Do not run this as root. Run it as your desktop user; it uses sudo only if needed."
fi

USER_NAME="$(id -un)"
USER_GROUP="$(id -gn)"
SSD_BASE="${CACHE2SSD_BASE:-/var/home}"      # env override = tests only
SSD_DIR="$SSD_BASE/$USER_NAME"
FLAGS_DIR="$(installsh_flags_dir)" || die "Cannot determine the installSH flags directory."
REGISTRY="$FLAGS_DIR/cache_to_ssd.tsv"
HOME_DIR="$(realpath -s -- "$HOME")"

require_cmd rsync realpath flock du df lsof stat readlink

REG_ORIG=()
REG_TARGET=()
REG_ADDED=()
REG_NEEDS_REWRITE=0
SIZE_BYTES=0
MOVE_TMP=""

# Take the registry lock for the rest of the process (fd 9).
# $1 = -x (exclusive, for changes) or -s (shared, for listing).
lock_registry() {
    mkdir -p -- "$FLAGS_DIR" || die "Cannot create $FLAGS_DIR"
    chmod 0700 -- "$FLAGS_DIR" 2>/dev/null || true
    exec 9>>"$REGISTRY.lock" || die "Cannot open $REGISTRY.lock"
    if ! flock -n "$1" 9; then
        die "Another cache_To_SSD.sh run is in progress (lock: $REGISTRY.lock)."
    fi
}

# Relative registry field -> absolute path (old absolute lines pass through).
abs_path() {    # <field> <base>
    case "$1" in
        /*)
            [[ "$1" == "$2"/* ]] || warn "Registry entry outside $2 kept as is: $1"
            REG_NEEDS_REWRITE=1
            printf '%s' "$1"
            ;;
        *)  printf '%s/%s' "$2" "$1" ;;
    esac
}

# Absolute path -> relative registry field (only if under base).
rel_path() {    # <path> <base>
    if [[ "$1" == "$2"/* ]]; then
        printf '%s' "${1#"$2"/}"
    else
        printf '%s' "$1"
    fi
}

load_registry() {
    REG_ORIG=(); REG_TARGET=(); REG_ADDED=(); REG_NEEDS_REWRITE=0
    [[ -f "$REGISTRY" ]] || return 0
    local o t a
    while IFS=$'\t' read -r o t a || [[ -n "$o" ]]; do
        [[ -n "$o" && -n "$t" ]] || continue
        case "$o" in /*) REG_NEEDS_REWRITE=1 ;; esac
        case "$t" in /*) REG_NEEDS_REWRITE=1 ;; esac
        REG_ORIG+=("$(abs_path "$o" "$HOME_DIR")")
        REG_TARGET+=("$(abs_path "$t" "$SSD_DIR")")
        REG_ADDED+=("${a:-}")
    done <"$REGISTRY"
}

# Atomically rewrite the registry from the REG_* arrays (relative form).
save_registry() {
    local tmp i
    mkdir -p -- "$FLAGS_DIR" || return 1
    tmp="$(mktemp "$FLAGS_DIR/.cache_to_ssd.XXXXXX")" || return 1
    for i in "${!REG_ORIG[@]}"; do
        printf '%s\t%s\t%s\n' \
            "$(rel_path "${REG_ORIG[$i]}" "$HOME_DIR")" \
            "$(rel_path "${REG_TARGET[$i]}" "$SSD_DIR")" \
            "${REG_ADDED[$i]}"
    done >"$tmp" || { rm -f -- "$tmp"; return 1; }
    chmod 0600 -- "$tmp" 2>/dev/null || true
    if ! mv -f -- "$tmp" "$REGISTRY"; then
        rm -f -- "$tmp"
        return 1
    fi
    REG_NEEDS_REWRITE=0
}

# Keep chezmoi's copy of the registry in sync. Never fails the script.
# Only for a registry inside $HOME (sandbox/test registries are skipped).
sync_chezmoi() {
    [[ "${CACHE2SSD_NO_CHEZMOI:-0}" == 1 ]] && return 0
    [[ "$REGISTRY" == "$HOME_DIR"/* && -f "$REGISTRY" ]] || return 0
    command -v chezmoi >/dev/null 2>&1 || return 0
    if chezmoi source-path -- "$REGISTRY" >/dev/null 2>&1; then
        chezmoi re-add -- "$REGISTRY" >/dev/null 2>&1 \
            || warn "chezmoi re-add failed for $REGISTRY"
    elif chezmoi add -- "$REGISTRY" >/dev/null 2>&1; then
        info "Now tracked by chezmoi: $REGISTRY"
    else
        warn "chezmoi add failed for $REGISTRY"
    fi
}

persist_registry() {
    save_registry || return 1
    sync_chezmoi
}

confirm() {
    local answer=""
    read -r -p "❓ $1 [y/N] " answer || answer=""
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || printf '%s bytes' "$1"; }

# Print leftover temp paths from an interrupted run next to $1; return 0 if any.
find_leftover() {
    local f found=()
    for f in "$1$TMP_SUFFIX"*; do
        [[ -e "$f" || -L "$f" ]] && found+=("$f")
    done
    (( ${#found[@]} )) || return 1
    printf '   %s\n' "${found[@]}" >&2
    return 0
}

check_leftover() {
    if find_leftover "$1"; then
        die "Leftover from an interrupted run found (above). Inspect it and remove or restore it first."
    fi
}

# Warn and ask if any process has files open below $1. Returns 1 if the user says no.
check_open_files() {
    local dir="$1" procs
    procs="$(lsof -w +D "$dir" 2>/dev/null | awk 'NR > 1 { print "   " $1 " (pid " $2 ")" }' | sort -u || true)"
    [[ -z "$procs" ]] && return 0
    warn "These processes have files open in $dir:"
    printf '%s\n' "$procs" >&2
    confirm "Continue anyway?"
}

# check_space <dir_to_copy> <dest_dir_on_target_fs> [soft]
# Sets SIZE_BYTES. Dies when it does not fit, or returns 1 in soft mode.
check_space() {
    local size avail need msg
    if ! size="$(du -sb -- "$1" 2>/dev/null | cut -f1)" || [[ -z "$size" ]]; then
        msg="Cannot measure size of $1"
        [[ "${3:-}" == soft ]] && { warn "$msg"; return 1; }
        die "$msg"
    fi
    if ! avail="$(df -B1 --output=avail -- "$2" 2>/dev/null | tail -n1 | tr -d ' ')" || [[ -z "$avail" ]]; then
        msg="Cannot read free space of $2"
        [[ "${3:-}" == soft ]] && { warn "$msg"; return 1; }
        die "$msg"
    fi
    need=$(( size + size / 20 ))
    if (( need > avail )); then
        msg="Not enough space: $1 needs $(human "$size") (+5%), $2 has $(human "$avail") free."
        [[ "${3:-}" == soft ]] && { warn "$msg"; return 1; }
        die "$msg"
    fi
    SIZE_BYTES="$size"
}

# copy_verify <src_dir> <dst_dir>: copy, then require a checksum dry-run to show no differences.
# (-l/--specials so symlinks and fifos are compared instead of reported as "skipping".)
copy_verify() {
    local src="$1" dst="$2" diff_out
    info "Copying $src → $dst"
    if ! rsync -aH --info=progress2 -- "$src/" "$dst/"; then
        warn "Copy failed."
        return 1
    fi
    restorecon -R -- "$dst" >/dev/null 2>&1 || true
    info "Verifying (checksums)…"
    if ! diff_out="$(rsync -rlcn --specials --itemize-changes -- "$src/" "$dst/")" || [[ -n "$diff_out" ]]; then
        warn "Verification failed:"
        [[ -n "${diff_out:-}" ]] && head -n 20 <<<"$diff_out" >&2
        return 1
    fi
}

# move_to_ssd <src> <target>: copy + verify + swap src for a symlink.
# <target> must be missing or an empty directory. On success the old copy is
# left at $MOVE_TMP (caller: finish_move or undo_move). Returns 1 on failure
# with the original untouched (warns instead of dying, so --restore continues).
move_to_ssd() {
    local src="$1" target="$2" ts
    MOVE_TMP=""
    if [[ ! -d "$target" ]] && ! mkdir -- "$target"; then
        warn "Could not create $target"
        return 1
    fi
    if ! copy_verify "$src" "$target"; then
        rm -rf -- "$target"
        warn "Aborted. Original left untouched: $src"
        return 1
    fi

    ts="$(date +%Y%m%d-%H%M%S)"
    MOVE_TMP="$src$TMP_SUFFIX$ts"
    if ! mv -- "$src" "$MOVE_TMP"; then
        rm -rf -- "$target"
        MOVE_TMP=""
        warn "Could not rename $src. Original left untouched."
        return 1
    fi
    if ! ln -s -- "$target" "$src"; then
        if ! mv -- "$MOVE_TMP" "$src"; then
            die "Could not create the symlink AND could not restore $src from $MOVE_TMP. Fix manually."
        fi
        rm -rf -- "$target"
        MOVE_TMP=""
        warn "Could not create symlink. Original restored: $src"
        return 1
    fi
}

finish_move() {
    [[ -n "$MOVE_TMP" ]] || return 0
    if ! rm -rf -- "$MOVE_TMP"; then
        warn "Could not fully delete the old copy $MOVE_TMP. Remove it manually."
    fi
    MOVE_TMP=""
}

undo_move() {   # <src> <target>
    rm -f -- "$1"
    mv -- "$MOVE_TMP" "$1" || die "Could not restore $1 from $MOVE_TMP. Fix manually."
    rm -rf -- "$2"
    MOVE_TMP=""
}

target_taken() {
    local cand="$1" t
    [[ -e "$cand" || -L "$cand" ]] && return 0
    for t in "${REG_TARGET[@]}"; do
        [[ "$t" == "$cand" ]] && return 0
    done
    return 1
}

pick_target() {
    local src="$1" name parent cand n
    name="$(basename -- "$src")"
    cand="$SSD_DIR/$name"
    target_taken "$cand" || { printf '%s' "$cand"; return 0; }

    parent="$(basename -- "$(dirname -- "$src")")"
    parent="${parent#"${parent%%[!.]*}"}"     # strip leading dots
    [[ -n "$parent" ]] || parent="home"
    cand="$SSD_DIR/${parent}_$name"
    target_taken "$cand" || { printf '%s' "$cand"; return 0; }

    n=2
    while target_taken "$SSD_DIR/${parent}_$name-$n"; do n=$((n + 1)); done
    printf '%s' "$SSD_DIR/${parent}_$name-$n"
}

ensure_ssd_dir() {
    if [[ ! -d "$SSD_DIR" ]]; then
        info "Creating $SSD_DIR (needs sudo)"
        if ! sudo mkdir -p -- "$SSD_DIR" \
           || ! sudo chown -- "$USER_NAME:$USER_GROUP" "$SSD_DIR" \
           || ! sudo chmod 0700 -- "$SSD_DIR"; then
            die "Could not create $SSD_DIR"
        fi
        sudo restorecon -- "$SSD_DIR" >/dev/null 2>&1 || true
    fi
    [[ -w "$SSD_DIR" ]] || die "$SSD_DIR is not writable by $USER_NAME."
}

# entry_state <orig> <target>: sets STATE (and STATE_INFO)
#   ok        orig is a symlink to target, target is a directory
#   dead      orig is a symlink to target, target is gone
#   elsewhere orig is a symlink to something else (STATE_INFO = link)
#   folder    orig is a normal directory (not moved yet)
#   notdir    orig exists but is not a directory
#   missing   orig does not exist
entry_state() {
    local o="$1" t="$2" link
    STATE_INFO=""
    if [[ -L "$o" ]]; then
        link="$(readlink -- "$o")"
        if [[ "$link" != "$t" ]]; then
            STATE="elsewhere"; STATE_INFO="$link"
        elif [[ -d "$t" && ! -L "$t" ]]; then
            STATE="ok"
        else
            STATE="dead"
        fi
    elif [[ -d "$o" ]]; then
        STATE="folder"
    elif [[ -e "$o" ]]; then
        STATE="notdir"
    else
        STATE="missing"
    fi
}

remove_entry() {    # <array index>
    local i="$1"
    unset 'REG_ORIG[i]' 'REG_TARGET[i]' 'REG_ADDED[i]'
    REG_ORIG=("${REG_ORIG[@]}"); REG_TARGET=("${REG_TARGET[@]}"); REG_ADDED=("${REG_ADDED[@]}")
}

# --------------------------------------------------------------- actions ----

do_list() {
    load_registry
    if (( ${#REG_ORIG[@]} == 0 )); then
        echo "No folders moved yet."
        return 0
    fi
    local i o t note
    for i in "${!REG_ORIG[@]}"; do
        o="${REG_ORIG[$i]}"; t="${REG_TARGET[$i]}"
        entry_state "$o" "$t"
        case "$STATE" in
            ok)        note="" ;;
            dead)      note="not restored (SSD copy gone)" ;;
            elsewhere) note="link points to $STATE_INFO, expected $t" ;;
            folder)    note="not moved (normal folder, run --restore)" ;;
            notdir)    note="not a directory" ;;
            missing)   note="not restored (path missing)" ;;
        esac
        if [[ -n "$note" ]]; then
            printf '%d. %s ⚠️ %s\n' "$((i + 1))" "$o" "$note"
        else
            printf '%d. %s\n' "$((i + 1))" "$o"
        fi
    done
}

do_list_not_restored() {
    load_registry
    if (( ${#REG_ORIG[@]} == 0 )); then
        echo "No folders moved yet."
        return 0
    fi
    local i any=0
    for i in "${!REG_ORIG[@]}"; do
        entry_state "${REG_ORIG[$i]}" "${REG_TARGET[$i]}"
        if [[ "$STATE" == missing || "$STATE" == dead ]]; then
            printf '%d. %s\n' "$((i + 1))" "${REG_ORIG[$i]}"
            any=1
        fi
    done
    (( any )) || echo "All saved paths are restored."
}

do_add() {
    local input="$1" src src_real ssd_real o target
    [[ -n "$input" ]] || die "--add needs a path."
    if [[ "$input" == *$'\t'* || "$input" == *$'\n'* ]]; then
        die "Paths containing TAB or newline are not supported."
    fi
    if [[ ! -e "$input" && ! -L "$input" ]]; then
        echo "⏭️  Skipped: $input does not exist."
        exit 0
    fi
    src="$(realpath -s -- "$input" 2>/dev/null)" || die "Cannot resolve path: $input"

    [[ "$src" == "$HOME_DIR"/* ]] || die "$src is not inside $HOME_DIR."
    [[ -L "$src" ]] && die "$src is a symlink (already moved? → $(readlink -- "$src"))."
    [[ -d "$src" ]] || die "$src is not a directory."

    lock_registry -x
    load_registry

    for o in "${REG_ORIG[@]}"; do
        [[ "$src" == "$o" ]] && die "$src is already registered (use --restore to re-apply it)."
        [[ "$src" == "$o"/* ]] && die "$src is inside the already moved folder $o."
        [[ "$o" == "$src"/* ]] && die "$src contains the already moved folder $o. Revert that first."
    done
    if [[ "$src" == "$SSD_DIR" || "$src" == "$SSD_DIR"/* ]]; then
        die "$src is inside $SSD_DIR."
    fi

    ensure_ssd_dir
    ssd_real="$(realpath -- "$SSD_DIR")"
    src_real="$(realpath -- "$src")"
    if [[ "$src_real" == "$ssd_real" || "$src_real" == "$ssd_real"/* ]]; then
        die "$src resolves to $src_real, which is inside $SSD_DIR."
    fi
    if [[ "$(stat -c %d -- "$src")" == "$(stat -c %d -- "$SSD_DIR")" ]]; then
        die "$src is already on the same filesystem as $SSD_DIR. Nothing to gain."
    fi

    check_leftover "$src"
    target="$(pick_target "$src")"
    check_space "$src" "$SSD_DIR"
    check_open_files "$src" || { echo "⏭️  Cancelled."; return 0; }

    confirm "Move $src → $target ($(human "$SIZE_BYTES"))?" || { echo "⏭️  Cancelled."; return 0; }

    move_to_ssd "$src" "$target" || die "Nothing changed."

    REG_ORIG+=("$src"); REG_TARGET+=("$target"); REG_ADDED+=("$(date -Iseconds)")
    if ! save_registry; then
        undo_move "$src" "$target"
        die "Could not write $REGISTRY. Original restored: $src"
    fi
    sync_chezmoi
    finish_move

    ok "$src → $target"
    echo
    do_list
}

do_restore() {
    lock_registry -x
    load_registry

    local count=${#REG_ORIG[@]}
    if (( count == 0 )); then
        echo "No folders saved yet. Nothing to restore."
        return 0
    fi

    local i o t n_ok=0 n_missing=0 n_moved=0 n_failed=0 n_skipped=0
    local -a moves=() deads=() conflicts=() sizes=()
    local need_ssd=0

    # Pass 1: classify
    for i in "${!REG_ORIG[@]}"; do
        o="${REG_ORIG[$i]}"; t="${REG_TARGET[$i]}"
        entry_state "$o" "$t"
        case "$STATE" in
            ok)        n_ok=$((n_ok + 1)) ;;
            dead)      deads+=("$i") ;;
            missing)   n_missing=$((n_missing + 1)) ;;
            elsewhere) conflicts+=("$((i + 1)). $o: link points to $STATE_INFO, expected $t") ;;
            notdir)    conflicts+=("$((i + 1)). $o: exists but is not a directory") ;;
            folder)    moves+=("$i"); need_ssd=1 ;;
        esac
    done

    # Pass 2: checks for folders to move (conflict instead of dying)
    if (( need_ssd )); then
        ensure_ssd_dir
        local -a checked=()
        for i in "${moves[@]}"; do
            o="${REG_ORIG[$i]}"; t="${REG_TARGET[$i]}"
            if [[ "$(stat -c %d -- "$o")" == "$(stat -c %d -- "$SSD_DIR")" ]]; then
                conflicts+=("$((i + 1)). $o: already on the same filesystem as $SSD_DIR")
            elif [[ -L "$t" || ( -e "$t" && ! -d "$t" ) ]]; then
                conflicts+=("$((i + 1)). $o: $t exists and is not a plain directory")
            elif [[ -d "$t" && -n "$(ls -A -- "$t" 2>/dev/null)" ]]; then
                conflicts+=("$((i + 1)). $o: $t already exists and is not empty")
            elif find_leftover "$o" 2>/dev/null; then
                conflicts+=("$((i + 1)). $o: leftover $o$TMP_SUFFIX* from an interrupted run")
            else
                checked+=("$i")
                sizes+=("$(du -sb -- "$o" 2>/dev/null | cut -f1 || echo 0)")
            fi
        done
        moves=("${checked[@]}")
    fi

    # Summary + one confirmation
    local k
    echo "Restore plan (${count} saved):"
    if (( ${#moves[@]} )); then
        echo "  Move to SSD:"
        for k in "${!moves[@]}"; do
            i="${moves[$k]}"
            printf '    %d. %s → %s (%s)\n' "$((i + 1))" "${REG_ORIG[$i]}" "${REG_TARGET[$i]}" "$(human "${sizes[$k]:-0}")"
        done
    fi
    if (( ${#deads[@]} )); then
        echo "  Dead links to remove (SSD copy gone, counted as not restored):"
        for i in "${deads[@]}"; do
            printf '    %d. %s\n' "$((i + 1))" "${REG_ORIG[$i]}"
        done
    fi
    echo "  Already on SSD: $n_ok"
    echo "  Path missing (skipped): $n_missing"
    if (( ${#conflicts[@]} )); then
        echo "  Conflicts (skipped, fix by hand):"
        printf '    %s\n' "${conflicts[@]}"
    fi

    if (( ${#moves[@]} == 0 && ${#deads[@]} == 0 )); then
        echo
        ok "Nothing to do."
        (( REG_NEEDS_REWRITE )) && { persist_registry || warn "Could not rewrite $REGISTRY"; }
        (( n_missing )) && echo "👉 See: $0 --list-not-restore"
        return 0
    fi

    echo
    confirm "Apply: move ${#moves[@]} folder(s), remove ${#deads[@]} dead link(s)?" \
        || { echo "⏭️  Cancelled."; return 0; }

    # Dead links -> missing
    for i in "${deads[@]}"; do
        o="${REG_ORIG[$i]}"; t="${REG_TARGET[$i]}"
        entry_state "$o" "$t"
        if [[ "$STATE" == dead ]] && rm -f -- "$o"; then
            echo "🧹 Removed dead link: $o"
        else
            warn "Could not remove dead link: $o"
        fi
        n_missing=$((n_missing + 1))
    done

    # Moves
    for i in "${moves[@]}"; do
        o="${REG_ORIG[$i]}"; t="${REG_TARGET[$i]}"
        echo
        info "[$((i + 1))] $o"
        if ! check_open_files "$o"; then
            echo "⏭️  Skipped."
            n_skipped=$((n_skipped + 1))
            continue
        fi
        if ! check_space "$o" "$SSD_DIR" soft; then
            n_failed=$((n_failed + 1))
            continue
        fi
        if move_to_ssd "$o" "$t"; then
            finish_move
            ok "$o → $t"
            n_moved=$((n_moved + 1))
        else
            n_failed=$((n_failed + 1))
        fi
    done

    (( REG_NEEDS_REWRITE )) && { persist_registry || warn "Could not rewrite $REGISTRY"; }

    echo
    echo "Done: moved $n_moved, already on SSD $n_ok, not restored (path missing) $n_missing," \
         "conflicts ${#conflicts[@]}, skipped $n_skipped, failed $n_failed."
    (( n_missing )) && echo "👉 See: $0 --list-not-restore"
    (( n_failed == 0 ))
}

do_revert() {
    local idx="$1" count orig target ts tmp i
    [[ "$idx" =~ ^[1-9][0-9]*$ ]] || die "Invalid index: '$idx' (see --list)."

    lock_registry -x
    load_registry
    count=${#REG_ORIG[@]}
    (( count > 0 )) || die "No folders moved yet."
    (( idx <= count )) || die "Invalid index: $idx (valid: 1-$count)."

    i=$((idx - 1))
    orig="${REG_ORIG[$i]}"
    target="${REG_TARGET[$i]}"

    entry_state "$orig" "$target"
    case "$STATE" in
        elsewhere) die "$orig points to $STATE_INFO, not $target. Changed by hand? Fix it manually." ;;
        folder|notdir) die "$orig exists and is not a symlink (changed by hand?). Leaving everything as is." ;;
    esac

    # Nothing left to move back: offer to forget the entry.
    if [[ ! -d "$target" || -L "$target" ]]; then
        confirm "Nothing to move back for $orig (SSD copy $target is gone). Remove entry $idx from the list?" \
            || { echo "⏭️  Cancelled."; return 0; }
        if [[ "$STATE" == dead ]] && ! rm -f -- "$orig"; then
            die "Could not remove dead link $orig."
        fi
        remove_entry "$i"
        persist_registry || die "Could not write $REGISTRY."
        ok "Removed entry $idx ($orig)"
        echo
        do_list
        return 0
    fi

    [[ -d "$(dirname -- "$orig")" ]] || die "Parent directory of $orig is missing."

    check_leftover "$orig"
    check_open_files "$target" || { echo "⏭️  Cancelled."; return 0; }
    check_space "$target" "$(dirname -- "$orig")"

    confirm "Move $target → $orig ($(human "$SIZE_BYTES"))?" || { echo "⏭️  Cancelled."; return 0; }

    ts="$(date +%Y%m%d-%H%M%S)"
    tmp="$orig$TMP_SUFFIX$ts"
    if ! copy_verify "$target" "$tmp"; then
        rm -rf -- "$tmp"
        die "Aborted. Nothing changed: $orig still points to $target"
    fi

    if [[ -L "$orig" ]] && ! rm -f -- "$orig"; then
        rm -rf -- "$tmp"
        die "Could not remove symlink $orig. Nothing changed."
    fi
    if ! mv -- "$tmp" "$orig"; then
        ln -s -- "$target" "$orig" 2>/dev/null || true
        die "Could not move $tmp to $orig. Symlink restored; copy left at $tmp."
    fi
    restorecon -R -- "$orig" >/dev/null 2>&1 || true

    remove_entry "$i"
    if ! persist_registry; then
        warn "Restored $orig, but could not update $REGISTRY. Remove line $idx by hand."
    fi

    if ! rm -rf -- "$target"; then
        warn "Could not fully delete $target. Remove it manually."
    fi

    ok "restored $orig"
    echo
    do_list
}

# ------------------------------------------------------------------ main ----

[[ $# -gt 0 ]] || { usage; exit 1; }

case "$1" in
    --add|-a)
        [[ $# -eq 2 ]] || die "Usage: $0 --add <PATH>"
        do_add "$2"
        ;;
    --list|-ls)
        [[ $# -eq 1 ]] || die "Usage: $0 --list"
        lock_registry -s
        do_list
        ;;
    --list-not-restore|-lsNrst)
        [[ $# -eq 1 ]] || die "Usage: $0 --list-not-restore"
        lock_registry -s
        do_list_not_restored
        ;;
    --restore|-rst)
        [[ $# -eq 1 ]] || die "Usage: $0 --restore"
        do_restore
        ;;
    --revert|-r)
        [[ $# -eq 2 ]] || die "Usage: $0 --revert <INDEX>"
        do_revert "$2"
        ;;
    --help|-h)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
