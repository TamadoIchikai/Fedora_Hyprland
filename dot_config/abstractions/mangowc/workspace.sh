#!/usr/bin/env bash
#
# mangowc/workspace.sh — MangoWC workspace (tag) operations.

# MangoWC tags are 1..9; parking tag is 9.
WM_PARK_WORKSPACE=9

WM_workspace_active() {
    # Selected tag of the focused monitor (`active_tags[0]`).
    local mon
    mon="$(WM_monitor_focused 2>/dev/null)"
    mmsg get all-monitors 2>/dev/null \
        | jq -r --arg m "$mon" \
            '(.monitors[] | select(.name == $m) | .active_tags[0]) // empty'
}
