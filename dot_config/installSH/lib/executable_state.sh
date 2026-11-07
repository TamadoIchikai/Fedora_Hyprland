#!/usr/bin/env bash
#
# state.sh - installation flag helpers shared by installSH scripts.
#
# Flags are plain key=value metadata files under:
#   ~/.config/installSH/flags/<id>.env
#
# IMPORTANT: flags are data, never code. Read them with installsh_flag_get
# (which uses grep/cut); never `source` a flag file.
#
# Root-run installers (for example apps_zen.sh) can source this file and write
# flags as the desktop user via SUDO_USER / INSTALLSH_TARGET_USER.

installsh_target_user() {
    printf '%s' "${INSTALLSH_TARGET_USER:-${SUDO_USER:-$USER}}"
}

installsh_target_home() {
    local user home

    user="$(installsh_target_user)"

    if [[ -n "${INSTALLSH_TARGET_HOME:-}" ]]; then
        printf '%s' "$INSTALLSH_TARGET_HOME"
        return 0
    fi

    home="$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || true)"
    if [[ -n "$home" ]]; then
        printf '%s' "$home"
        return 0
    fi

    # Last-resort fallback for systems without getent.
    if [[ "$user" == "${USER:-}" ]]; then
        printf '%s' "$HOME"
        return 0
    fi

    return 1
}

installsh_flags_dir() {
    local home

    if [[ -n "${INSTALLSH_FLAGS_DIR:-}" ]]; then
        printf '%s' "$INSTALLSH_FLAGS_DIR"
        return 0
    fi

    home="$(installsh_target_home)" || return 1
    printf '%s/.config/installSH/flags' "$home"
}

# installsh_flag_write <id> key=value [key=value ...]
installsh_flag_write() {
    local id="$1"
    shift

    if [[ ! "$id" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
        printf 'state: invalid flag id: %s\n' "$id" >&2
        return 1
    fi

    local dir tmp key value kv
    dir="$(installsh_flags_dir)" || return 1
    mkdir -p -- "$dir" || return 1
    chmod 0700 -- "$dir" 2>/dev/null || true

    tmp="$(mktemp "$dir/.${id}.XXXXXX")" || return 1

    {
        printf 'id=%s\n' "$id"
        for kv in "$@"; do
            key="${kv%%=*}"
            value="${kv#*=}"
            if [[ "$key" =~ ^[a-z_][a-z0-9_]*$ ]]; then
                printf '%s=%s\n' "$key" "$value"
            fi
        done
    } >"$tmp" || {
        rm -f -- "$tmp"
        return 1
    }

    chmod 0600 -- "$tmp" 2>/dev/null || true

    if ! mv -f -- "$tmp" "$dir/$id.env"; then
        rm -f -- "$tmp"
        return 1
    fi

    # If a root-run installer wrote the flag, give it back to the desktop user.
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        chown -- "$(installsh_target_user):" "$dir" "$dir/$id.env" 2>/dev/null || true
    fi
}

# installsh_flag_get <file> <key>
installsh_flag_get() {
    local file="$1"
    local key="$2"
    local line

    [[ -r "$file" ]] || return 1
    [[ "$key" =~ ^[a-z_][a-z0-9_]*$ ]] || return 1

    line="$(grep -m1 -E "^${key}=" -- "$file" 2>/dev/null || true)"
    [[ -n "$line" ]] || return 1

    printf '%s\n' "${line#*=}"
}

# installsh_flag_remove <id>
installsh_flag_remove() {
    local id="$1"
    local dir

    [[ "$id" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || return 1

    dir="$(installsh_flags_dir)" || return 1
    rm -f -- "$dir/$id.env"
}

# installsh_flag_list
installsh_flag_list() {
    local dir

    dir="$(installsh_flags_dir)" || return 1
    [[ -d "$dir" ]] || return 0

    find "$dir" -maxdepth 1 -type f -name '*.env' -printf '%p\n' 2>/dev/null | sort
}

# installsh_github_token
#
# Print a GitHub token from the first source that has one:
#   1. $GITHUB_TOKEN or $GH_TOKEN (already exported)
#   2. $INSTALLSH_GITHUB_TOKEN_FILE
#   3. <target-home>/.config/installSH/github-token
#   4. <target-home>/.config/update-check/github-token
#
# Returns 1 when no token is configured, so callers can use:
#   token="$(installsh_github_token || true)"
#
# Token files are data: they are read, never sourced. A file may contain a bare
# token or a GITHUB_TOKEN=... / GH_TOKEN=... line; blank lines and comments are
# ignored. Keep token files at mode 0600.
installsh_github_token() {
    local token home file

    token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    if [[ -n "$token" ]]; then
        printf '%s' "$token"
        return 0
    fi

    home="$(installsh_target_home 2>/dev/null || printf '%s' "$HOME")"

    for file in \
        "${INSTALLSH_GITHUB_TOKEN_FILE:-}" \
        "$home/.config/installSH/github-token" \
        "$home/.config/update-check/github-token"
    do
        [[ -n "$file" && -r "$file" ]] || continue

        token="$(awk '
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*$/ { next }
            {
                sub(/\r$/, "")
                sub(/^[[:space:]]*/, "")
                sub(/[[:space:]]*$/, "")
                sub(/^export[[:space:]]+/, "")
                sub(/^(GITHUB_TOKEN|GH_TOKEN)=/, "")
                print
                exit
            }
        ' "$file" 2>/dev/null || true)"

        if [[ -n "$token" ]]; then
            printf '%s' "$token"
            return 0
        fi
    done

    return 1
}
