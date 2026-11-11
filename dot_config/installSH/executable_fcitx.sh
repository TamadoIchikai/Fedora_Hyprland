#!/usr/bin/env bash
# Input method: Fcitx5 with Vietnamese (Unikey) and Japanese (Mozc).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

dnf_install fcitx5 fcitx5-configtool fcitx5-unikey fcitx5-mozc
