#!/usr/bin/env bash
# Desktop apps: KeePassXC + Flatpak apps and their per-app sandbox overrides.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Shared NTFS drive (see the post-install notes in install.sh).
SHARED_DRIVE="${SHARED_DRIVE:-/mnt/sda2}"

dnf_install keepassxc

flatpak_install \
  com.obsproject.Studio \
  io.missioncenter.MissionCenter \
  eu.betterbird.Betterbird \
  com.github.tchx84.Flatseal \
  md.obsidian.Obsidian \
  net.ankiweb.Anki

flatpak override --user \
  --filesystem="$SHARED_DRIVE/BetterBird/" \
  --filesystem=~/Downloads/tmp/ \
  --env=GTK_USE_PORTAL=1 \
  eu.betterbird.Betterbird

# Obsidian: offline, only the vault on the shared drive.
flatpak override --user \
  --unshare=network \
  --filesystem="$SHARED_DRIVE/Obsidian" \
  md.obsidian.Obsidian

# LocalSend (installed by apps_AppImages.sh) needs port 53317 open.
sudo firewall-cmd --permanent --add-port=53317/tcp --add-port=53317/udp
sudo firewall-cmd --reload
