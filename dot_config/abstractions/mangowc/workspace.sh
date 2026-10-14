#!/usr/bin/env bash
#
# mangowc/workspace.sh — MangoWC workspace (tag) operations.

# MangoWC tags are 1..9; parking tag is 9.
WM_PARK_WORKSPACE=9

WM_workspace_active() {
    # TODO(mango): verify how to read the selected tag of the focused monitor.
    mmsg get tags 2>/dev/null | jq -r '[.[] | select(.selected == true or .is_selected == true)][0].id // empty'
}
