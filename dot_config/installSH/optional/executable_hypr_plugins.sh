#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# hypr_plugins.sh - Build & install Hyprland plugins via hyprpm on Fedora
# ----------------------------------------------------------------------------
# 1. Installs the build deps (hyprland-devel at the INSTALLED Hyprland EVR)
# 2. Builds + enables the plugin via hyprpm at a pinned git rev
# 3. Locks Hyprland + its ABI libs with dnf versionlock (survives dnf update)
# 4. Verifies the plugin loads the way it will at login (`hyprpm reload`)
#
# Build deps are intentionally KEPT: `hyprpm reload` (run at every login to
# load the plugin) validates its headers with `pkgconf --cflags hyprland`,
# which needs the *-devel .pc files (aquamarine, hyprutils, cairo, ...).
# Removing them makes every new session load no plugins at all.
#
# Run as your normal user (NOT root): hyprpm needs your Hyprland session and
# its per-user cache (/var/cache/hyprpm/$USER), and calls sudo by itself.
# The password is asked ONCE (see sudo_setup).
# ============================================================================

# --- Plugin definition ------------------------------------------------------
PLUGIN_URL="https://github.com/sandwichfarm/hyprexpo"
PLUGIN_NAME="hyprexpo"          # also the build output (hyprexpo.so)

# Shared pins (HYPRLAND_EVR, HYPREXPO_REV, VERSIONLOCK, HYPR_LOCK_PKGS).
# Env vars win over the file defaults; see versions.env for the bump workflow.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../versions.env
source "$SCRIPT_DIR/../versions.env"

TOOLCHAIN=(meson ninja-build gcc gcc-c++ make git cmake pkgconf-pkg-config cpio)
# hyprpm's header hash covers Hyprland's commit AND these libs' versions;
# upgrading any of them makes hyprpm refuse to load the plugin at login.
read -r -a LOCK_PKGS <<< "${HYPR_LOCK_PKGS:-hyprland}"
# hyprpm cache: /var/cache/hyprpm/$USER (current) or ~/.local/share/hyprpm (old)
HYPRPM_DIRS=("/var/cache/hyprpm/${USER:-$(id -un)}" "$HOME/.local/share/hyprpm")
HYPR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

FORCE=0
TMP_DIR=""
KEEPALIVE_PID=""
RESOLVED_REV=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 <mode> [options]

Modes:
  --install     Install build deps, add + enable + load the plugin, lock versions
  --update      Rebuild headers/plugins (after a version bump), re-lock
  --uninstall   Disable + remove the plugin and its version locks

Options:
  --force       Remove and re-add the plugin repository (clean rebuild)
  -h, --help    Show this help

Version pinning (versions.env):
  HYPREXPO_REV empty  -> newest hyprexpo tag matching the installed Hyprland
  HYPREXPO_REV set    -> validated against the installed Hyprland (drift aborts)
  VERSIONLOCK=1       -> lock HYPR_LOCK_PKGS + hyprland-devel after a good build
  e.g.  HYPREXPO_REV=v0.57.2+1 $0 --install --force
EOF
}

warn() { echo "⚠️  $*" >&2; }
die()  { echo "❌ $*" >&2; exit 1; }

on_exit() {
  [[ -n "$KEEPALIVE_PID" ]] && kill "$KEEPALIVE_PID" 2>/dev/null
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf -- "$TMP_DIR"
  return 0
}
trap on_exit EXIT

in_session() { [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; }

# One password prompt for the whole run.
#  - hyprpm wraps every privileged step as `sudo <cmd>; sudo echo hyprland;
#    sudo -k`, and `-k` wipes the cached credential -> next sudo re-prompts.
#    A `sudo` shim first in PATH (hyprpm resolves sudo via PATH) turns -k/-K
#    into no-ops; everything else goes to the real sudo.
#  - A background `sudo -v` loop stops the 5-min timeout expiring during the
#    long Hyprland-header/plugin builds.
sudo_setup() {
  local real
  real="$(command -v sudo)" || die "'sudo' is required."
  mkdir -p "$TMP_DIR/bin"
  cat > "$TMP_DIR/bin/sudo" <<SH
#!/bin/sh
case "\${1:-}" in
  -K) exit 0 ;;
  -k) shift; [ \$# -eq 0 ] && exit 0 ;;
esac
exec "$real" "\$@"
SH
  chmod +x "$TMP_DIR/bin/sudo"
  export PATH="$TMP_DIR/bin:$PATH"

  echo "🔑 Root is needed for dnf / versionlock / hyprpm (asked once)."
  sudo -v || die "sudo authentication failed."
  ( while kill -0 "$$" 2>/dev/null; do sleep 45; "$real" -n -v 2>/dev/null || exit 0; done ) &
  KEEPALIVE_PID=$!
}

installed_evr() { rpm -q --qf '%{EVR}\n' "$1" 2>/dev/null | head -n1; }

install_pkgs() {
  local -a missing=()
  mapfile -t missing < <(rpm -q "$@" 2>/dev/null | sed -n 's/^package \(.*\) is not installed$/\1/p')
  (( ${#missing[@]} )) || return 0
  echo "📦 Installing: ${missing[*]}"
  sudo dnf install -y --setopt=install_weak_deps=False "${missing[@]}"
}

# ---------------------------------------------------------------------------
# Versions
# ---------------------------------------------------------------------------
tag_from_version() { sed -n 's/^Tag:[[:space:]]*\([^,[:space:]]*\).*/\1/p' | head -n1; }
installed_hyprland_tag() { Hyprland --version 2>/dev/null | tag_from_version; }

# Refuse to build for the wrong compositor; flag a stale versions.env.
preflight_versions() {
  local evr installed running
  evr="$(installed_evr hyprland)"
  [[ -n "$evr" ]] || die "hyprland is not installed."
  if [[ -n "${HYPRLAND_EVR:-}" && "$evr" != "$HYPRLAND_EVR" ]]; then
    warn "Installed hyprland is $evr but versions.env pins $HYPRLAND_EVR; building for $evr (update versions.env)."
  fi
  if in_session; then
    installed="$(installed_hyprland_tag)"
    running="$(hyprctl version 2>/dev/null | tag_from_version)"
    [[ -z "$running" || "$running" == "$installed" ]] \
      || die "Running Hyprland is $running but installed is $installed. Log out/in (or reboot) first."
  fi
}

# Sets RESOLVED_REV: validated HYPREXPO_REV, or the newest matching tag.
resolve_hyprexpo_rev() {
  local hl_tag hl_ver
  hl_tag="$(installed_hyprland_tag)"
  [[ -n "$hl_tag" ]] || die "Could not parse the installed Hyprland tag (Hyprland --version)."
  hl_ver="${hl_tag#v}"

  if [[ -n "$HYPREXPO_REV" ]]; then
    [[ "$HYPREXPO_REV" == "v$hl_ver" || "$HYPREXPO_REV" == "v$hl_ver+"* || "$HYPREXPO_REV" =~ ^[0-9a-fA-F]{7,40}$ ]] \
      || die "HYPREXPO_REV='$HYPREXPO_REV' does not match installed Hyprland $hl_tag (expected 'v$hl_ver' or 'v$hl_ver+N')."
    RESOLVED_REV="$HYPREXPO_REV"
    echo "📌 Using pinned hyprexpo rev: $RESOLVED_REV (Hyprland $hl_tag)"
    return 0
  fi

  echo "🔎 Resolving newest hyprexpo tag for Hyprland $hl_tag..."
  RESOLVED_REV="$(git ls-remote --tags --refs "$PLUGIN_URL" 2>/dev/null \
    | awk -F/ '{print $NF}' | grep -E "^v${hl_ver//./\\.}([+][0-9]+)?$" | sort -V | tail -n1 || true)"
  [[ -n "$RESOLVED_REV" ]] \
    || die "No hyprexpo tag for Hyprland $hl_tag yet. Wait for a release, or set HYPREXPO_REV in versions.env."
  echo "✅ Matched hyprexpo tag: $RESOLVED_REV"
}

# Lock LOCK_PKGS + hyprland-devel to the exact EVR just built against.
apply_versionlock() {
  if [[ "${VERSIONLOCK:-1}" != "1" ]]; then
    warn "VERSIONLOCK=0: not locking; a dnf upgrade of ${LOCK_PKGS[*]} WILL break the plugin at next login."
    return 0
  fi
  local -a names=() specs=()
  local p evr
  for p in "${LOCK_PKGS[@]}" hyprland-devel; do
    evr="$(installed_evr "$p")"
    [[ -n "$evr" ]] || { warn "$p not installed; not locking it."; continue; }
    names+=("$p"); specs+=("$p-$evr")
  done
  (( ${#specs[@]} )) || return 0
  echo "🔒 Locking: ${specs[*]}"
  sudo dnf versionlock delete "${names[@]}" >/dev/null 2>&1 || true
  sudo dnf versionlock add "${specs[@]}" >/dev/null || warn "dnf versionlock add failed."
}

# ---------------------------------------------------------------------------
# Lua shim
# ---------------------------------------------------------------------------
# hyprexpo for Hyprland 0.57 demands Lua 5.5 dev files (upstream moved to
# 5.5), but Fedora's COPR Hyprland links liblua-5.4 and Fedora ships no 5.5.
# The plugin must match the running compositor, so expose Fedora's lua.pc as
# "lua5.5" for this process only. hyprpm builds with
# PKG_CONFIG_PATH="<headers>:$PKG_CONFIG_PATH", so the export reaches make.
setup_lua_shim() {
  pkg-config --exists 'lua >= 5.5' 2>/dev/null && return 0
  ldd "$(command -v Hyprland)" 2>/dev/null | grep -q 'liblua-5\.4' || return 0
  pkg-config --exists lua 2>/dev/null || { warn "lua-devel missing; cannot create the Lua shim."; return 0; }
  mkdir -p "$TMP_DIR/pkgconfig"
  cat > "$TMP_DIR/pkgconfig/lua5.5.pc" <<PC
Name: Lua
Description: Fedora Lua $(pkg-config --modversion lua) exposed as 5.5 (Hyprland here links liblua-5.4)
Version: 5.5.0
Cflags: $(pkg-config --cflags lua)
Libs: $(pkg-config --libs lua)
PC
  export PKG_CONFIG_PATH="$TMP_DIR/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  echo "🩹 Hyprland links Lua 5.4: building against it via a temporary lua5.5.pc shim."
}

# ---------------------------------------------------------------------------
# Plugin
# ---------------------------------------------------------------------------
plugin_present() { hyprpm list 2>/dev/null | grep -qi "$PLUGIN_NAME"; }
plugin_loaded()  { hyprctl plugin list 2>/dev/null | grep -qi "$PLUGIN_NAME"; }
hyprpm_remove()  { hyprpm remove "$PLUGIN_NAME" || hyprpm remove "$PLUGIN_URL" || true; }

find_plugin_so() {
  local d
  for d in "${HYPRPM_DIRS[@]}"; do
    [[ -d "$d" ]] && find "$d" -name "$PLUGIN_NAME.so" 2>/dev/null || true
  done | head -n1
}

# Reproduce what happens at login: unload, then `hyprpm reload`. This catches
# outdated headers / missing .pc files that a still-loaded plugin would hide.
verify_plugin() {
  local so
  so="$(find_plugin_so)"
  [[ -n "$so" ]] || { warn "could not locate $PLUGIN_NAME.so under ${HYPRPM_DIRS[*]}"; return 1; }
  if ldd "$so" 2>/dev/null | grep -q 'not found'; then
    echo "  ❌ $so has missing shared libraries:"; ldd "$so" | grep 'not found'; return 1
  fi
  echo "  ✅ shared libraries resolve: $so"

  if ! in_session; then
    warn "Not inside a Hyprland session; skipping the login-load test."
    return 0
  fi
  plugin_loaded && hyprctl plugin unload "$so" >/dev/null 2>&1 || true
  hyprpm reload || true
  if plugin_loaded; then
    echo "  ✅ loads via 'hyprpm reload' (same as at login)"
  else
    echo "  ❌ 'hyprpm reload' did not load $PLUGIN_NAME; it will be missing next session"; return 1
  fi
}

# Plugins are only loaded when something runs `hyprpm reload` at login.
check_login_hook() {
  if grep -rqs 'hyprpm reload' "$HYPR_CONFIG_DIR"; then
    echo "  ✅ login hook found ('hyprpm reload' in $HYPR_CONFIG_DIR)"
  else
    warn "Nothing runs 'hyprpm reload' at login, so the plugin won't load next session. Add to hyprland.lua:"
    echo '      hl.on("hyprland.start", function() hl.exec_cmd("hyprpm reload") end)' >&2
  fi
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
prepare_build() {
  preflight_versions
  sudo_setup
  echo "📦 Ensuring toolchain + build deps..."
  # hyprland-devel pinned to the installed EVR so it can never drag hyprland
  # forward mid-session. These stay installed (see header).
  install_pkgs "${TOOLCHAIN[@]}" "hyprland-devel-$(installed_evr hyprland)" \
    || die "Could not install build deps (COPR may have dropped this build). Bump per versions.env, log out/in, rerun."
  setup_lua_shim
}

finish_build() {
  echo "🔎 Verifying plugin..."
  if verify_plugin; then
    apply_versionlock
  else
    warn "Verification failed; NOT locking versions. Inspect 'hyprpm reload -v' / 'hyprpm update -v'."
  fi
  check_login_hook
}

do_install() {
  preflight_versions
  resolve_hyprexpo_rev   # before installing anything: fail fast
  prepare_build

  # Drop the old repo BEFORE `hyprpm update`, otherwise update rebuilds it at
  # its old rev / manifest pin and aborts before the pinned rev is added.
  if plugin_present; then
    if (( FORCE )); then
      echo "♻️  Removing existing plugin repository..."; hyprpm_remove
    else
      echo "✅ Plugin repository already present (use --force to rebuild)."
    fi
  fi

  echo "🧩 Updating Hyprland headers (hyprpm update)..."
  hyprpm update || die "hyprpm update failed (see: hyprpm update -v)."

  if ! plugin_present; then
    echo "🔗 Adding $PLUGIN_URL @ $RESOLVED_REV"
    hyprpm add "$PLUGIN_URL" "$RESOLVED_REV" || die "hyprpm add failed."
  fi
  hyprpm enable "$PLUGIN_NAME" || warn "'hyprpm enable' failed (already enabled?)."

  finish_build
  echo "🎉 $PLUGIN_NAME @ $RESOLVED_REV installed. Bind: hl.plugin.hyprexpo.expo(\"toggle\")"
}

do_update() {
  prepare_build
  echo "🔄 Updating headers + plugins..."
  hyprpm update || die "hyprpm update failed (see: hyprpm update -v)."
  finish_build
}

do_uninstall() {
  local ans
  read -r -p "❓ Disable + remove $PLUGIN_NAME and its version locks? (hyprland.lua is not touched) [y/N] " ans
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]] || { echo "Cancelled."; exit 0; }
  sudo_setup
  hyprpm disable "$PLUGIN_NAME" || warn "disable reported an issue."
  hyprpm_remove
  hyprpm reload || true
  if [[ "${VERSIONLOCK:-1}" == "1" ]]; then
    sudo dnf versionlock delete "${LOCK_PKGS[@]}" hyprland-devel >/dev/null 2>&1 || true
    echo "🔓 Removed version locks."
  fi
  echo "🎉 $PLUGIN_NAME uninstalled. Build deps were kept; drop them with: sudo dnf remove hyprland-devel"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
MODE=""
while (( $# )); do
  case "$1" in
    --install|--update|--uninstall) MODE="${1#--}" ;;
    --force)   FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Invalid flag: $1" ;;
  esac
  shift
done
[[ -n "$MODE" ]] || { usage; exit 1; }

(( EUID != 0 )) || die "Run as your normal user, not root/sudo: hyprpm needs your session and per-user cache (password is asked once)."
command -v hyprpm  >/dev/null || die "'hyprpm' not found (part of the hyprland package)."
command -v hyprctl >/dev/null || die "'hyprctl' not found (part of the hyprland package)."
TMP_DIR="$(mktemp -d /tmp/hypr_plugins.XXXXXX)"

case "$MODE" in
  install)   do_install ;;
  update)    do_update ;;
  uninstall) do_uninstall ;;
esac
