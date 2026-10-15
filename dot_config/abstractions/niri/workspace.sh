#!/usr/bin/env bash
#
# niri/workspace.sh — niri workspace operations.

# niri's workspaces are otherwise dynamic (scrollable). To reproduce the fixed
# "trash" workspace from Hyprland (11) / MangoWC (9), the niri config declares
# persistent NAMED workspaces "1".."11" (declaration order gives them stable
# indices 1..11). Workspace "11" is the parking workspace and is deliberately
# left out of the Alt+1..0 binds. Matching the other backends keeps the shared
# autostart/abstraction code identical.
WM_PARK_WORKSPACE=11

WM_workspace_active() {
    # Unique id of the focused workspace (numeric, as other backends return).
    niri msg --json workspaces 2>/dev/null \
        | jq -r '.[] | select(.is_focused == true) | .id' | head -n1
}
