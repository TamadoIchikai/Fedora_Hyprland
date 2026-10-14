#!/usr/bin/env bash
#
# common.sh — compositor-agnostic helpers, always sourced first by wm.sh.
# Must remain portable across bash and zsh (the API is sourced by both).

WM_err() {
    printf 'wm-api: %s\n' "$*" >&2
}

WM_have() {
    command -v "$1" >/dev/null 2>&1
}

WM_require() {
    local c
    for c in "$@"; do
        WM_have "$c" || { WM_err "missing required command: $c"; return 1; }
    done
}

# Print the parking workspace/tag for the running compositor.
# Set by each backend's workspace.sh (Hyprland 11, MangoWC 9).
WM_park_workspace() {
    printf '%s' "${WM_PARK_WORKSPACE:-}"
}

# Strict allowlists for values interpolated into compositor command strings.
# These reject the quote/bracket/backslash characters that could break out of
# the Lua or mmsg argument the value is embedded in.
WM_monitor_name_valid() { [[ "${1:-}" =~ ^[A-Za-z0-9._-]+$ ]]; }
WM_mode_valid()         { [[ "${1:-}" =~ ^[A-Za-z0-9@._xX-]+$ ]]; }
WM_number_valid()       { [[ "${1:-}" =~ ^[0-9]*\.?[0-9]+$ ]]; }

# Emit a Lua single-quoted string literal for arbitrary text.
WM_lua_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\'/\\\'}"
    printf "'%s'" "$s"
}

# Emit a Lua long-bracket string literal, choosing a bracket level that does
# not collide with the content so the value can never break out of the string.
WM_lua_long() {
    local s="$1" eq=""
    while :; do
        case "$s" in
            *"]$eq]"*) eq="$eq=" ;;
            *) break ;;
        esac
    done
    printf '[%s[%s]%s]' "$eq" "$s" "$eq"
}
