#!/usr/bin/env bash
# Claude Code (and Zed's Claude agent) only reads ~/.claude/skills.
script="$HOME/.config/installSH/apps_zed.sh"
[[ -x "$script" ]] || exit 0
exec "$script" --link-skills
