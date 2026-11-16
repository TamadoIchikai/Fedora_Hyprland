#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# hypr_plugins.sh - Build & install Hyprland plugins via hyprpm on Fedora
# ----------------------------------------------------------------------------
# 1. Installs the build closure (hyprland-devel at the INSTALLED Hyprland EVR)
# 2. Builds + enables the plugin via hyprpm at a pinned git rev
# 3. Locks Hyprland + its ABI libs with dnf versionlock (survives dnf update)
# 4. Removes every package the run pulled in, except runtime libraries
#
# Run as your normal user (NOT root): hyprpm needs your Hyprland session and
# its per-user cache (/var/cache/hyprpm/$USER), and calls sudo by itself.
# You are asked for your password ONCE; a background keepalive refreshes the
# sudo timestamp so the long Hyprland/plugin builds don't let it expire.
# ============================================================================

# --- Plugin definition ------------------------------------------------------
PLUGIN_URL="https://github.com/sandwichfarm/hyprexpo"
PLUGIN_NAME="hyprexpo"          # also the build output (hyprexpo.so)

# Shared pins (HYPRLAND_EVR, HYPREXPO_REV, VERSIONLOCK, HYPR_LOCK_PKGS).
# Env vars win over the file defaults; see versions.env for the bump workflow.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../versions.env
source "$SCRIPT_DIR/../versions.env"

# --- Package sets -----------------------------------------------------------
# Toolchain the rest of installSH keeps anyway (never removed).
KEEP_BASE=(meson ninja-build gcc gcc-c++ make git git-core cmake
  pkgconf pkgconf-pkg-config cpio)
# Runtime libraries; never removed. Extended at runtime with whatever the
# built .so actually links against (protect_plugin_runtime).
RUNTIME=(hyprland lua-libs hyprlang hyprutils hyprcursor hyprgraphics
  libwayland-server libxkbcommon libpixman-1 libdrm libinput)
# hyprpm's header hash covers Hyprland's commit AND these libs' versions;
# upgrading any of them makes hyprpm refuse to load the plugin at boot.
read -r -a LOCK_PKGS <<< "${HYPR_LOCK_PKGS:-hyprland}"

# hyprpm build output: current hyprpm uses /var/cache/hyprpm/$USER, older
# releases ~/.local/share/hyprpm.
HYPRPM_DIRS=("/var/cache/hyprpm/${USER:-$(id -un)}" "$HOME/.local/share/hyprpm")

# Packages pulled in by a run; persisted so --cleanup works after a failure.
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr_plugins/deps.txt"

FORCE=0
KEEP_DEPS=0
TMP_DIR=""
KEEPALIVE_PID=""
RESOLVED_REV=""

# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 <mode> [options]

Modes:
  --install     Install build deps, add + enable + load the plugin, lock
                versions, then remove build-only deps (keeps runtime libs)
  --update      Rebuild headers/plugins (e.g. after a version bump), re-lock,
                clean up
  --cleanup     Remove build-only deps recorded by a previous (failed) run
  --uninstall   Disable + remove the plugin and its version locks

Options:
  --force       Remove and re-add the plugin repository (clean rebuild)
  --keep-deps   Skip the post-install dependency cleanup
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

in_list() {
  local needle="$1" item; shift
  for item in "$@"; do [[ "$needle" == "$item" ]] && return 0; done
  return 1
}

in_session() { [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; }

# Ask for the password once, then keep the sudo timestamp fresh until exit.
# hyprpm's own sudo calls share this terminal's timestamp, so they won't
# prompt again either.
sudo_begin() {
  [[ -n "$KEEPALIVE_PID" ]] && return 0
  echo "🔑 Root is needed for dnf / versionlock / hyprpm installs (asked once)."
  sudo -v || die "sudo authentication failed."
  ( while kill -0 "$$" 2>/dev/null; do sleep 45; sudo -n -v 2>/dev/null || exit 0; done ) &
  KEEPALIVE_PID=$!
}

installed_evr() { rpm -q --qf '%{EVR}\n' "$1" 2>/dev/null | head -n1; }

# Prints the subset of the given package names that are NOT installed.
missing_pkgs() {
  (( $# )) || return 0
  rpm -q "$@" 2>/dev/null | sed -n 's/^package \(.*\) is not installed$/\1/p'
}

install_pkgs() {
  local -a missing=()
  mapfile -t missing < <(missing_pkgs "$@")
  (( ${#missing[@]} )) || return 0
  echo "📦 Installing: ${missing[*]}"
  sudo dnf install -y --setopt=install_weak_deps=False "${missing[@]}"
}

pkg_snapshot() { rpm -qa --qf '%{NAME}\n' | sort -u; }

load_state() { [[ -f "$STATE_FILE" ]] && sed '/^[[:space:]]*$/d' "$STATE_FILE"; return 0; }

# Merge packages added since $TMP_DIR/pre.txt into the state file right away,
# so a later failure (build error, Ctrl-C) stays recoverable with --cleanup.
record_new_pkgs() {
  local -a merged=()
  mapfile -t merged < <( { load_state; comm -13 "$TMP_DIR/pre.txt" <(pkg_snapshot); } | sort -u )
  (( ${#merged[@]} )) || return 0
  mkdir -p "${STATE_FILE%/*}"
  printf '%s\n' "${merged[@]}" > "$STATE_FILE"
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

# Lock everything in LOCK_PKGS (plus hyprland-devel, which cleanup removes
# but which must not be able to drag hyprland forward on a later reinstall)
# to the exact EVR the plugin was just built against. One delete + one add.
apply_versionlock() {
  if [[ "${VERSIONLOCK:-1}" != "1" ]]; then
    warn "VERSIONLOCK=0: not locking; a dnf upgrade of ${LOCK_PKGS[*]} WILL break the plugin on next boot."
    return 0
  fi
  local -a names=() specs=()
  local p evr
  for p in "${LOCK_PKGS[@]}" hyprland-devel; do
    evr="$(installed_evr "${p/#hyprland-devel/hyprland}")"
    [[ -n "$evr" ]] || { warn "$p not installed; not locking it."; continue; }
    names+=("$p"); specs+=("$p-$evr")
  done
  (( ${#specs[@]} )) || return 0
  echo "🔒 Locking: ${specs[*]}"
  sudo dnf versionlock delete "${names[@]}" >/dev/null 2>&1 || true
  sudo dnf versionlock add "${specs[@]}" >/dev/null || warn "dnf versionlock add failed."
}

remove_versionlock() {
  sudo dnf versionlock delete "${LOCK_PKGS[@]}" hyprland-devel >/dev/null 2>&1 || true
  echo "🔓 Removed version locks for ${LOCK_PKGS[*]} hyprland-devel."
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

hyprpm_remove() { hyprpm remove "$PLUGIN_NAME" || hyprpm remove "$PLUGIN_URL" || true; }

find_plugin_so() {
  local d
  for d in "${HYPRPM_DIRS[@]}"; do
    [[ -d "$d" ]] && find "$d" -name "$PLUGIN_NAME.so" 2>/dev/null || true
  done | head -n1
}

verify_plugin() {
  local ok=0 so
  so="$(find_plugin_so)"
  if [[ -z "$so" ]]; then
    warn "could not locate $PLUGIN_NAME.so under ${HYPRPM_DIRS[*]}"; ok=1
  elif ldd "$so" 2>/dev/null | grep -q 'not found'; then
    echo "  ❌ $so has missing shared libraries:"; ldd "$so" | grep 'not found'; ok=1
  else
    echo "  ✅ shared libraries resolve: $so"
  fi
  if in_session; then
    if plugin_loaded; then echo "  ✅ plugin loaded: $PLUGIN_NAME"
    else echo "  ❌ plugin NOT shown by 'hyprctl plugin list'"; ok=1; fi
  else
    warn "Not inside a Hyprland session; skipping load check."
  fi
  return "$ok"
}

# Add the packages providing libs the built .so links against to RUNTIME.
protect_plugin_runtime() {
  local so; local -a libs=() pkgs=()
  so="$(find_plugin_so)"
  [[ -n "$so" ]] || return 0
  mapfile -t libs < <(ldd "$so" 2>/dev/null | grep -oE '/[^ ]+\.so[^ ]*')
  (( ${#libs[@]} )) || return 0
  mapfile -t pkgs < <(rpm -qf --qf '%{NAME}\n' "${libs[@]}" 2>/dev/null | grep -v ' ' | sort -u)
  RUNTIME+=("${pkgs[@]}")
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
# Remove recorded build-only packages, minus runtime/toolchain, minus anything
# still required by a package outside the set. `rpm -e --test` checks the
# whole set in one go; blockers are dropped and the check repeats.
cleanup_deps() {
  local -a targets=() caps=() keep=() next=()
  local p out
  protect_plugin_runtime
  while IFS= read -r p; do
    in_list "$p" "${RUNTIME[@]}" "${KEEP_BASE[@]}" || targets+=("$p")
  done < <( { load_state; echo hyprland-devel; } | sort -u )
  mapfile -t targets < <(comm -12 <(printf '%s\n' "${targets[@]}" | sort -u) <(pkg_snapshot))

  while (( ${#targets[@]} )); do
    out="$(LC_ALL=C rpm -e --test "${targets[@]}" 2>&1)" && break
    mapfile -t caps < <(sed -n 's/^[[:space:]]*\(.*\) is needed by (installed) .*/\1/p' <<<"$out" | awk '{print $1}' | sort -u)
    mapfile -t keep < <( (( ${#caps[@]} )) && rpm -q --whatprovides "${caps[@]}" --qf '%{NAME}\n' 2>/dev/null | grep -v ' ' | sort -u)
    next=()
    for p in "${targets[@]}"; do in_list "$p" "${keep[@]}" || next+=("$p"); done
    if (( ${#next[@]} == ${#targets[@]} )); then
      warn "Could not resolve removal blockers; leaving packages installed:"; echo "$out" >&2
      return 0
    fi
    warn "Keeping (still required elsewhere): $(comm -23 <(printf '%s\n' "${targets[@]}" | sort) <(printf '%s\n' "${next[@]}" | sort) | tr '\n' ' ')"
    targets=("${next[@]}")
  done

  if (( ${#targets[@]} )); then
    echo "🗑️  Removing ${#targets[@]} build-only packages..."
    sudo_begin
    sudo dnf remove -y --no-autoremove "${targets[@]}"
  else
    echo "🔎 No build-only packages to remove."
  fi
  rm -f -- "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
# Shared front half of install/update: deps, shim. Leaves sudo warm.
prepare_build() {
  TMP_DIR="$(mktemp -d /tmp/hypr_plugins.XXXXXX)"
  pkg_snapshot > "$TMP_DIR/pre.txt"
  sudo_begin

  echo "📦 Ensuring toolchain + build deps..."
  # hyprland-devel pinned to the installed EVR: installing it can never
  # upgrade hyprland itself mid-session.
  install_pkgs "${KEEP_BASE[@]}" "hyprland-devel-$(installed_evr hyprland)" \
    || die "Could not install build deps (COPR may have dropped this build). Bump per versions.env, log out/in, rerun."
  record_new_pkgs
  setup_lua_shim
}

# Shared back half: verify, lock on success, clean up.
finish_build() {
  echo "🔎 Verifying plugin..."
  if verify_plugin; then
    apply_versionlock
  else
    warn "Verification failed; NOT locking versions. Inspect 'hyprctl plugin list' / 'hyprpm update -v'."
  fi
  record_new_pkgs
  if (( KEEP_DEPS )); then
    echo "⏭️  --keep-deps: leaving build deps installed (remove later with --cleanup)."
  else
    echo "🧹 Cleaning up build-only dependencies..."
    cleanup_deps
    if in_session; then
      if plugin_loaded; then echo "  ✅ plugin still loaded"; else warn "plugin no longer listed after cleanup."; fi
    fi
  fi
  return 0
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
  hyprpm update || die "hyprpm update failed (see: hyprpm update -v). Build deps are recorded; run '$0 --cleanup'."

  if ! plugin_present; then
    echo "🔗 Adding $PLUGIN_URL @ $RESOLVED_REV"
    hyprpm add "$PLUGIN_URL" "$RESOLVED_REV" || die "hyprpm add failed. Run '$0 --cleanup' to remove build deps."
  fi
  hyprpm enable "$PLUGIN_NAME" || warn "'hyprpm enable' failed (already enabled?)."
  hyprpm reload || warn "hyprpm reload reported an issue."

  finish_build
  echo "🎉 $PLUGIN_NAME @ $RESOLVED_REV installed. Bind: hl.plugin.hyprexpo.expo(\"toggle\")"
}

do_update() {
  preflight_versions
  prepare_build
  echo "🔄 Updating headers + plugins..."
  hyprpm update || die "hyprpm update failed. Run '$0 --cleanup' to remove build deps."
  hyprpm reload || warn "hyprpm reload reported an issue."
  finish_build
}

do_uninstall() {
  local ans
  read -r -p "❓ Disable + remove $PLUGIN_NAME and its version locks? (hyprland.lua is not touched) [y/N] " ans
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]] || { echo "Cancelled."; exit 0; }
  sudo_begin
  hyprpm disable "$PLUGIN_NAME" || warn "disable reported an issue."
  hyprpm_remove
  hyprpm reload || true
  [[ "${VERSIONLOCK:-1}" == "1" ]] && remove_versionlock
  cleanup_deps
  echo "🎉 $PLUGIN_NAME uninstalled."
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
MODE=""
while (( $# )); do
  case "$1" in
    --install|--update|--cleanup|--uninstall) MODE="${1#--}" ;;
    --force)     FORCE=1 ;;
    --keep-deps) KEEP_DEPS=1 ;;
    -h|--help)   usage; exit 0 ;;
    *) usage >&2; die "Invalid flag: $1" ;;
  esac
  shift
done
[[ -n "$MODE" ]] || { usage; exit 1; }

(( EUID != 0 )) || die "Run as your normal user, not root/sudo: hyprpm needs your session and per-user cache (you'll be asked for the password once)."
command -v sudo   >/dev/null || die "'sudo' is required."
command -v hyprpm >/dev/null || die "'hyprpm' not found (part of the hyprland package)."
command -v hyprctl >/dev/null || die "'hyprctl' not found (part of the hyprland package)."

case "$MODE" in
  install)   do_install ;;
  update)    do_update ;;
  cleanup)   cleanup_deps ;;
  uninstall) do_uninstall ;;
esac
