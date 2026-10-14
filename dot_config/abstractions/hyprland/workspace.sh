#!/usr/bin/env bash
#
# hyprland/workspace.sh — Hyprland workspace operations.

# Parking workspace for "parked" background apps. Hyprland keeps 11.
WM_PARK_WORKSPACE=11

WM_workspace_active() {
    hyprctl activeworkspace -j | jq -r '.id'
}
