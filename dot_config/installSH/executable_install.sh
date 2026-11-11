#!/usr/bin/env bash
# install.sh - run installSH step scripts in order on a fresh Fedora machine.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Exported so child scripts (via lib/common.sh) share the same palette.
export CYAN='\033[0;36m'
export BLUE_ON_WHITE='\033[0;34;47m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export RED='\033[0;31m'
export RED_ON_WHITE='\033[0;31;47m'
export NC='\033[0m'

# ============================================================================
# TASK REGISTRY
#   task "<description>" "<script path relative to installSH>" "<mode>" [args...]
#   mode: user     run as the current user (script uses sudo itself)
#         sudo     run the whole script as root (desktop user kept in env)
#   Tasks registered with `optional_task` are skipped by --all.
# ============================================================================
declare -a TASK_DESCS=() TASK_SCRIPTS=() TASK_MODES=() TASK_ARGS=() TASK_OPTIONAL=()

_register() {
  local optional="$1" desc="$2" script="$3" mode="$4"
  shift 4
  TASK_OPTIONAL+=("$optional")
  TASK_DESCS+=("$desc")
  TASK_SCRIPTS+=("$script")
  TASK_MODES+=("$mode")
  TASK_ARGS+=("$*") # args never contain spaces
}
task()          { _register 0 "$@"; }
optional_task() { _register 1 "$@"; }

# --- 1. Hardware & system base ---
task "WiFi & Nvidia drivers"                   wifi_nvidia.sh     user
task "Core: Hyprland (pinned) + base tooling"  core.sh            user
task "CLI & Wayland tools (foot, fuzzel, ...)" apps_CLI.sh        user
# --- 2. Desktop ---
task "Fonts & icons"                           fonts.sh           user
task "Input method (Fcitx5)"                   fcitx.sh           user
task "Waybar, notifications & media"           media.sh           user
task "File manager (Thunar) & default apps"    file_manager.sh    user
task "Unified dark theme (GTK/Qt/Flatpak)"     theme.sh           user
# --- 3. Applications ---
task "KeePassXC + Flatpak apps (Obsidian, Betterbird, Anki, ...)" apps_extra.sh user
task "Zed editor"                              apps_zed.sh        user --install
task "OpenTabletDriver"                        apps_opentablet.sh user
task "AppImages (LocalSend, Sioyek, Helium)"   apps_AppImages.sh  user --install all
task "Zotero"                                  apps_zotero.sh     user
task "Zen browser"                             apps_zen.sh        sudo --install
task "Cloudflare WARP"                         cloudflare.sh      user
# --- 4. Optional (never run by --all) ---
optional_task "Dev tools (uv, gcc, clangd)"            optional/apps_DevTools.sh               user
optional_task "VS Code"                                optional/apps_vscode.sh                 user
optional_task "Vivaldi"                                optional/apps_vivaldi.sh                user
optional_task "Mailspring"                             optional/apps_mailspring.sh             user
optional_task "Stylus Labs Write"                      optional/stylusLabsWrite.sh             user
optional_task "Xournal++ X11 launcher override"        optional/xournalpp_x11_desktopChange.sh user
optional_task "Hibernate + zram fix"                   optional/hibernateFix.sh                user
optional_task "TLP battery thresholds (ASUS laptop)"   optional/tlp_change.sh                  user
optional_task "Hyprland plugins (needs Hyprland session)" optional/hypr_plugins.sh             user --install
optional_task "MangoWC window manager"                 optional/wm_mangowm.sh                  sudo --install
optional_task "Restore Zen profile from shared drive"  optional/applyFirefoxConfig.sh          user

TOTAL_TASKS=${#TASK_SCRIPTS[@]}

# ============================================================================
# CLI
# ============================================================================
print_usage() {
  cat <<EOF
Usage:
  $0 --all                     Run all default (non-optional) tasks in order
  $0 --explicit "1, 3, 4"      Run only tasks 1, 3 and 4 (optional tasks allowed)
  $0 --explicit-range "1, 4"   Run tasks 1..4 (optional tasks in the range are skipped)
  $0 --explicit-range "3, BOT" Run from task 3 to the last default task
  $0 --list                    List all tasks and their indices
  $0 --list-check              List tasks and check the scripts exist / are executable
  $0 -v, --verbose             Trace child scripts (bash -x); combine with the above
  $0 -h, --help                Show this help
EOF
}

die() { echo -e "${RED_ON_WHITE}$*${NC}" >&2; exit 1; }

(($# == 0)) && { print_usage; exit 1; }

EXEC_MODE=""
TARGETS=""
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)            EXEC_MODE="all"; shift ;;
    --explicit)       EXEC_MODE="explicit"; TARGETS="${2:-}"; shift 2 || die "--explicit needs a value" ;;
    --explicit-range) EXEC_MODE="range"; TARGETS="${2:-}"; shift 2 || die "--explicit-range needs a value" ;;
    --list)           EXEC_MODE="list"; shift ;;
    --list-check)     EXEC_MODE="list-check"; shift ;;
    -v|--verbose)     VERBOSE=1; shift ;;
    -h|--help)        print_usage; exit 0 ;;
    *)                die "Unknown option $1" ;;
  esac
done

[[ -n "$EXEC_MODE" ]] || { print_usage; exit 1; }

task_label() {
  local i="$1" label="${TASK_DESCS[$1]}"
  [[ "${TASK_OPTIONAL[$i]}" == 1 ]] && label+=" ${YELLOW}(optional)${NC}"
  echo -e "$label"
}

# ============================================================================
# LIST MODES
# ============================================================================
if [[ "$EXEC_MODE" == "list" || "$EXEC_MODE" == "list-check" ]]; then
  echo -e "${CYAN}Registered installation tasks:${NC}"
  for ((i = 0; i < TOTAL_TASKS; i++)); do
    line="  [$((i + 1))/${TOTAL_TASKS}] $(task_label "$i")"
    if [[ "$EXEC_MODE" == "list-check" ]]; then
      path="$SCRIPT_DIR/${TASK_SCRIPTS[$i]}"
      if [[ ! -f "$path" ]]; then
        status="${RED_ON_WHITE}NOT FOUND${NC}"
      elif [[ ! -x "$path" ]]; then
        status="${YELLOW}Found, NOT executable${NC}"
      else
        status="${GREEN}Found & executable${NC}"
      fi
      line+=" -> ${TASK_SCRIPTS[$i]} $status"
    fi
    echo -e "$line"
  done
  exit 0
fi

# ============================================================================
# BUILD EXECUTION LIST
# ============================================================================
declare -a EXEC_INDICES=()
IFS=' ' read -r -a ARGS_ARR <<<"${TARGETS//,/ }"

is_index() { [[ "$1" =~ ^[0-9]+$ ]] && (($1 >= 1 && $1 <= TOTAL_TASKS)); }

case "$EXEC_MODE" in
  all)
    for ((i = 0; i < TOTAL_TASKS; i++)); do
      [[ "${TASK_OPTIONAL[$i]}" == 1 ]] || EXEC_INDICES+=("$i")
    done
    ;;
  explicit)
    for num in "${ARGS_ARR[@]}"; do
      is_index "$num" || die "Invalid task index: '$num' (valid: 1-${TOTAL_TASKS}, see --list)"
      EXEC_INDICES+=("$((num - 1))")
    done
    ;;
  range)
    ((${#ARGS_ARR[@]} == 2)) || die "--explicit-range needs exactly two values, e.g. \"3, BOT\""
    start="${ARGS_ARR[0]}"
    end="${ARGS_ARR[1]}"
    [[ "${end^^}" == "BOT" ]] && end="$TOTAL_TASKS"
    is_index "$start" || die "Invalid range start: '$start'"
    is_index "$end" || die "Invalid range end: '$end'"
    ((start <= end)) || die "Range start ($start) is after end ($end)"
    for ((i = start - 1; i < end; i++)); do
      [[ "${TASK_OPTIONAL[$i]}" == 1 ]] || EXEC_INDICES+=("$i")
    done
    ;;
esac

((${#EXEC_INDICES[@]} > 0)) || { echo -e "${YELLOW}No tasks selected.${NC}"; exit 0; }

# ============================================================================
# PREPARE
# ============================================================================
echo -e "${CYAN}==========================================${NC}"
echo -e "${GREEN}   Starting installation...   ${NC}"
echo -e "${CYAN}==========================================${NC}"

mkdir -p ~/Downloads/Systems/tmp ~/.local/bin ~/.local/share/fonts ~/.local/share/applications

# Installation flags used by the login update checker (~/.local/bin/update-check.sh)
INSTALLSH_TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
INSTALLSH_TARGET_HOME="$(getent passwd "$INSTALLSH_TARGET_USER" 2>/dev/null | cut -d: -f6 || true)"
[[ -n "$INSTALLSH_TARGET_HOME" ]] || INSTALLSH_TARGET_HOME="$HOME"
export INSTALLSH_TARGET_USER INSTALLSH_TARGET_HOME
export INSTALLSH_FLAGS_DIR="$INSTALLSH_TARGET_HOME/.config/installSH/flags"
mkdir -p "$INSTALLSH_FLAGS_DIR"
chmod 0700 "$INSTALLSH_FLAGS_DIR" 2>/dev/null || true

# Ask for the sudo password once and keep the timestamp fresh for long runs.
sudo -v
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

BASH_RUN=(bash)
((VERBOSE)) && BASH_RUN=(bash -x)
PRESERVE_ENV="INSTALLSH_TARGET_USER,INSTALLSH_TARGET_HOME,INSTALLSH_FLAGS_DIR,GITHUB_TOKEN,GH_TOKEN"

# ============================================================================
# EXECUTE
# ============================================================================
for idx in "${EXEC_INDICES[@]}"; do
  desc="${TASK_DESCS[$idx]}"
  script="${TASK_SCRIPTS[$idx]}"
  path="$SCRIPT_DIR/$script"
  display_idx=$((idx + 1))
  read -r -a args <<<"${TASK_ARGS[$idx]}"

  echo -e "\n${BLUE_ON_WHITE}======================================================${NC}"
  echo -e "${CYAN}--> [${display_idx}/${TOTAL_TASKS}] $desc  (${script} ${args[*]})${NC}"

  [[ -f "$path" ]] || die "✖ Script not found: $script"
  chmod +x "$path"

  cmd=("${BASH_RUN[@]}" "$path" "${args[@]}")
  [[ "${TASK_MODES[$idx]}" == "sudo" ]] && cmd=(sudo --preserve-env="$PRESERVE_ENV" "${cmd[@]}")

  if ! "${cmd[@]}"; then
    echo -e "${RED_ON_WHITE}✖ ✖ ✖ ✖ ✖ ✖ ✖ FAILED ✖ ✖ ✖ ✖ ✖ ✖${NC}"
    echo -e "${YELLOW}✖ Failed at step [${display_idx}]: $desc${NC}"
    echo -e "${YELLOW}  Resume with: $0 --explicit-range \"${display_idx}, BOT\"${NC}"
    exit 1
  fi
  echo -e "${GREEN}======================== DONE ========================${NC}"
done

# ============================================================================
# POST-INSTALL NOTES
# ============================================================================
echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}-------> ALL REQUESTED STEPS COMPLETED!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -en "${CYAN}"
cat <<'EOF'
Manual steps after installation:

1. Mount the shared drive (shared with Windows 11). It must be mounted at
   /mnt/sda2 so Syncthing, Resticprofile, Obsidian and Betterbird find it:
     sudo mkdir -p /mnt/sda2
     sudo mount /dev/sda2 /mnt/sda2
   Then open Obsidian -> "Linux setup" and follow the guide to mount it permanently.

2. Betterbird: open the current profile with
     flatpak run eu.betterbird.Betterbird -p

3. Syncthing (~/.config/systemd/user/syncthing.service):
     systemctl --user enable --now syncthing.service

4. Resticprofile backups:
     rclone config                       # set up the "gdrive" remote
     rclone lsd gdrive:                  # verify the remote
     resticprofile -c /mnt/sda2/Resticprofiles/profiles.yaml -n default snapshots
     resticprofile -c /mnt/sda2/Resticprofiles/profiles.yaml -n default schedule --all

5. Inside a Hyprland session, build the Hyprland plugins:
     ~/.config/installSH/install.sh --explicit <index of "Hyprland plugins">   (see --list)

6. Optional tasks (see --list), e.g. TLP battery thresholds on the ASUS laptop
   or restoring the Zen profile from the shared drive.
EOF
echo -en "${NC}"
