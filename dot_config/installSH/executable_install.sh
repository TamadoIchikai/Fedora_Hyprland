#!/usr/bin/env bash
set -euo pipefail

# Dynamically get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Export colors so child scripts can use them without redefining
export CYAN='\033[0;36m'
export BLUE_ON_WHITE='\033[0;34;47m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export RED_ON_WHITE='\033[0;31;47m'
export NC='\033[0m'

# --- USAGE ---
print_usage() {
  echo "Usage:"
  echo "  $0 --all                    : Explicitly run all scripts sequentially"
  echo "  $0 --explicit \"1, 3, 4\"     : Run only indices 1, 3, and 4"
  echo "  $0 --explicit-range \"1, 4\"  : Run from index 1 to 4"
  echo "  $0 --explicit-range \"3, BOT\": Run from index 3 to the last script"
  echo "  $0 --list                   : List all registered tasks and their indices"
  echo "  $0 --list-check             : List all tasks and check if the scripts exist/are executable"
  echo "  $0 -h, --help               : Show this help message"
}

# Show help if no arguments are passed
if (($# == 0)); then
  print_usage
  exit 1
fi

# --- ARGUMENT PARSING ---
EXEC_MODE=""
TARGETS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      EXEC_MODE="all"
      shift 1
      ;;
    --explicit)
      EXEC_MODE="explicit"
      TARGETS="$2"
      shift 2
      ;;
    --explicit-range)
      EXEC_MODE="range"
      TARGETS="$2"
      shift 2
      ;;
    --list)
      EXEC_MODE="list"
      shift 1
      ;;
    --list-check)
      EXEC_MODE="list-check"
      shift 1
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo -e "${RED_ON_WHITE}Unknown option $1${NC}"
      exit 1
      ;;
  esac
done

# --- TASK COLLECTION ---
declare -a TASK_DESCS=()
declare -a TASK_SCRIPTS=()

run_step() {
  TASK_DESCS+=("$1")
  TASK_SCRIPTS+=("$2")
}

# --- REGISTER SCRIPTS (1-indexed mapping for flags) ---
# 1. Hardware & System Base
run_step "WiFi & Nvidia Drivers" "wifi_nvidia.sh"
run_step "Core Packages (Hyprland)" "core.sh"

# 2. Fonts, Theming & UI
run_step "Fonts & Icons" "fonts.sh"
run_step "File Manager (Thunar & Config)" "file_manager.sh"
run_step "Keyboard Layout (Fcitx5)" "fcitx.sh"

# 3. Base Utilities
run_step "Waybar and Media Tools" "media.sh"
run_step "CLI Tools" "apps_CLI.sh"
run_step "VSCode" "apps_vscode.sh"
run_step "OpenTabletDriver" "apps_opentablet.sh"
run_step "Zen browser" "apps_zen.sh"
run_step "AppImages such as Obsidian, Sioyek and LocalSend" "apps_AppImages.sh --install all"
run_step "Anki" "apps_Anki.sh"
run_step "Zotero" "apps_zotero.sh"
run_step "Extra packages and unified dark theme" "apps_extra.sh"

TOTAL_TASKS=${#TASK_SCRIPTS[@]}

# --- LIST COMMANDS INTERCEPT ---
if [[ "$EXEC_MODE" == "list" ]]; then
  echo -e "${CYAN}Registered Installation Tasks:${NC}"
  for (( i=0; i<TOTAL_TASKS; i++ )); do
    display_idx=$((i + 1))
    echo "  [${display_idx}/${TOTAL_TASKS}]: ${TASK_DESCS[$i]}"
  done
  exit 0

elif [[ "$EXEC_MODE" == "list-check" ]]; then
  echo -e "${CYAN}Registered Tasks & Script Status:${NC}"
  for (( i=0; i<TOTAL_TASKS; i++ )); do
    display_idx=$((i + 1))
    script_path="$SCRIPT_DIR/${TASK_SCRIPTS[$i]}"
    
    if [[ -f "$script_path" ]]; then
      if [[ -x "$script_path" ]]; then
        status="${GREEN}Found & Executable${NC}"
      else
        status="${YELLOW}Found, NOT Executable${NC}"
      fi
    else
      status="${RED_ON_WHITE}NOT FOUND${NC}"
    fi
    
    echo -e "  [${display_idx}/${TOTAL_TASKS}]: ${TASK_DESCS[$i]} -> $status"
  done
  exit 0
fi

# --- INSTALLATION HEADER ---
echo -e "${CYAN}==========================================${NC}"
echo -e "${GREEN}   Starting Installation...   ${NC}"
echo -e "${CYAN}==========================================${NC}"

# Create base directories
mkdir -p ~/Downloads/Systems/tmp ~/.local/bin/ ~/.local/share/fonts/ ~/.local/share/applications/

# --- BUILD EXECUTION LIST ---
declare -a EXEC_INDICES=()

if [[ "$EXEC_MODE" == "all" ]]; then
  for (( i=0; i<TOTAL_TASKS; i++ )); do
    EXEC_INDICES+=("$i")
  done

elif [[ "$EXEC_MODE" == "explicit" ]]; then
  # Replace commas with spaces and read into array
  IFS=' ' read -r -a arr <<< "${TARGETS//,/ }"
  for num in "${arr[@]}"; do
    if [[ "$num" =~ ^[0-9]+$ ]]; then
      EXEC_INDICES+=("$((num - 1))") # Convert 1-based input to 0-based index
    fi
  done

elif [[ "$EXEC_MODE" == "range" ]]; then
  IFS=' ' read -r -a arr <<< "${TARGETS//,/ }"
  start_num="${arr[0]}"
  end_val="${arr[1]}"

  start_idx=$((start_num - 1))
  
  # Handle "BOT" (bottom) keyword
  if [[ "${end_val^^}" == "BOT" ]]; then
    end_idx=$((TOTAL_TASKS - 1))
  else
    end_idx=$((end_val - 1))
  fi

  for (( i=start_idx; i<=end_idx; i++ )); do
    if (( i >= 0 && i < TOTAL_TASKS )); then
      EXEC_INDICES+=("$i")
    fi
  done
fi

if [[ ${#EXEC_INDICES[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No steps selected to run. Check your index numbers.${NC}"
  exit 0
fi

# --- EXECUTE TASKS ---
for idx in "${EXEC_INDICES[@]}"; do
  # Catch out-of-bounds explicit indices gracefully
  if (( idx < 0 || idx >= TOTAL_TASKS )); then
    echo -e "${YELLOW}Warning: Skipping invalid index $((idx + 1))${NC}"
    continue
  fi

  desc="${TASK_DESCS[$idx]}"
  script_name="${TASK_SCRIPTS[$idx]}"
  script_path="$SCRIPT_DIR/$script_name"
  display_idx=$((idx + 1))

  echo -e "\n${BLUE_ON_WHITE}======================================================${NC}"
  echo -e "${CYAN}--> [${display_idx}/${TOTAL_TASKS}] Running : $desc ${NC}"

  if [[ -f "$script_path" ]]; then
    chmod +x "$script_path"
    if ! bash -x "$script_path"; then
      echo -e "${RED_ON_WHITE}✖ ✖ ✖ ✖ ✖ ✖ ✖ FAILED ✖ ✖ ✖ ✖ ✖ ✖${NC}"
      echo -e "${YELLOW}✖ Failed at step [${display_idx}]:  $desc${NC}"
      exit 1
    fi
    echo -e "${GREEN}======================== DONE ========================${NC}"
  else
    echo -e "${RED_ON_WHITE}✖ Script not found: $script_name${NC}"
    exit 1
  fi
done

echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}-------> ALL REQUESTED STEPS COMPLETED!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${CYAN}After installation steps: ${NC}"
echo -e "${CYAN}Open zen and then ~/.config/installSH/applyFirefoxConfig.sh to apply keyboard shortcuts and workspaces, etc ${NC}"
echo -e "${CYAN}flatpak run eu.betterbird.Betterbird --p to open betterbird current profile${NC}"
echo -e "${CYAN}~/.config/installSH/tlp_change.sh to apply bettery profile for laptop (ASUS) ${NC}"

