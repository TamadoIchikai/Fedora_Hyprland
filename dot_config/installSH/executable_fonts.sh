#!/usr/bin/env bash
# System fonts (Font Awesome, Noto CJK) + user fonts (Nerd Fonts, Libron).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

FONT_DIR="$HOME/.local/share/fonts"
NERD_FONTS_VERSION="v3.2.1"
LIBRON_VERSION="v0.25"

dnf_install fontawesome-fonts \
  google-noto-sans-jp-fonts google-noto-serif-jp-fonts google-noto-cjk-fonts
require_cmd wget unzip fc-cache

mkdir -p "$FONT_DIR"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
NEEDS_CACHE_REFRESH=false

# install_font_zip <name> <glob-inside-FONT_DIR> <url>
# Skips the download when a file matching the glob already exists.
install_font_zip() {
  local name="$1" glob="$2" url="$3"
  local -a existing
  shopt -s nullglob
  # shellcheck disable=SC2206 # intentional glob expansion
  existing=($FONT_DIR/$glob)
  shopt -u nullglob

  if ((${#existing[@]} > 0)); then
    echo "$name already installed. Skipping."
    return 0
  fi

  info "Installing $name..."
  wget -q -O "$TMP_DIR/$name.zip" "$url"
  unzip -o -qq "$TMP_DIR/$name.zip" -d "$FONT_DIR"
  NEEDS_CACHE_REFRESH=true
}

install_font_zip "JetBrainsMono Nerd Font" "*JetBrainsMono*Nerd*.ttf" \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/JetBrainsMono.zip"
install_font_zip "Nerd Fonts Symbols Only" "*SymbolsNerdFont*.ttf" \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/NerdFontsSymbolsOnly.zip"
install_font_zip "Libron" "*Libron*.ttf" \
  "https://github.com/nicoverbruggen/libron/releases/download/${LIBRON_VERSION}/Libron.zip"

if $NEEDS_CACHE_REFRESH; then
  fc-cache -f >/dev/null
fi
