#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# hypr_plugins.sh - Build & install Hyprland plugins via hyprpm on Fedora
# ----------------------------------------------------------------------------
# Installs the build-only dependency tree needed by hyprpm (via the
# `hyprland-devel` meta package), builds the plugin, then removes every
# package that was newly pulled in EXCEPT runtime dependencies.
#
# Run this as your normal user (NOT root): hyprpm needs your running
# Hyprland session and writes to ~/.local/share/hyprpm. Package operations
# are escalated with sudo internally.
# ============================================================================

# --- Plugin definition ------------------------------------------------------
PLUGIN_URL="https://github.com/sandwichfarm/hyprexpo"
PLUGIN_NAME="hyprexpo"          # also the build output (hyprexpo.so)

# Shared version pins (HYPREXPO_REV, ...). Env vars win over the file defaults;
# see versions.env for semantics and the Hyprland/hyprexpo bump workflow.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "$SCRIPT_DIR/versions.env"

# --- Package sets -----------------------------------------------------------
# Meta package that pulls the whole hyprpm/Hyprland-header build closure.
DEP_META=(hyprland-devel)
# Toolchain that the rest of installSH keeps anyway (never removed).
KEEP_BASE=(meson ninja-build gcc gcc-c++ make git git-core cmake \
  pkgconf pkgconf-pkg-config cpio)
# Runtime libraries the plugin/Hyprland need at runtime. All of these are
# already installed as dependencies of `hyprland`, so this is a safeguard:
# they must never be removed by the cleanup step.
RUNTIME=(hyprland lua-libs hyprlang hyprutils hyprcursor hyprgraphics \
  libwayland-server libxkbcommon libpixman-1 libdrm libinput)

# --- State (persisted so --cleanup works in a later run) --------------------
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr_plugins"
STATE_FILE="$STATE_DIR/deps.txt"

FORCE=0
KEEP_DEPS=0
TMP_DIR=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 <mode> [options]

Modes (choose one):
  --install     Install build deps, add + enable + load the plugin, then
                remove build-only deps (keeps runtime libraries)
  --update      Reinstall build deps, update all plugins, reload, then clean up
  --cleanup     Remove build-only deps recorded by a previous install/update
  --uninstall   Disable + remove the plugin, then clean up build deps

Options:
  --force       Rebuild/reinstall even if the plugin repository already exists
  --keep-deps   Skip the post-install dependency cleanup
  -h, --help    Show this help message

Version pinning:
  HYPREXPO_REV and HYPRLAND_EVR are read from versions.env (next to this
  script). When HYPREXPO_REV is empty the newest hyprexpo tag matching the
  installed Hyprland version is auto-resolved; when set it is validated
  against the installed Hyprland tag (drift aborts). hyprpm keeps the rev
  pinned across subsequent updates. Override ad hoc, e.g.:
      HYPREXPO_REV=v0.56.2+3 $0 --install --force

Run as your normal user (not root). sudo is used for dnf operations.
EOF
}

warn() { echo "⚠️  $*" >&2; }
die()  { echo "❌ $*" >&2; exit 1; }

cleanup_tmp() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf -- "$TMP_DIR"
}
trap cleanup_tmp EXIT

require_user() {
  if [[ ${EUID} -eq 0 ]]; then
    die "Run this as your normal user, not root (hyprpm needs your session; dnf is escalated via sudo)."
  fi
  command -v sudo >/dev/null 2>&1 || die "'sudo' is required for package operations."
}

require_hyprpm() {
  command -v hyprpm  >/dev/null 2>&1 || die "'hyprpm' not found (part of the hyprland package)."
  command -v hyprctl >/dev/null 2>&1 || die "'hyprctl' not found (part of the hyprland package)."
}

in_hyprland_session() {
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]
}

pkg_installed() { rpm -q "$1" >/dev/null 2>&1; }

is_in_list() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [[ "$needle" == "$item" ]] && return 0
  done
  return 1
}

install_pkgs() {
  local missing=() p
  for p in "$@"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if (( ${#missing[@]} == 0 )); then
    return 0
  fi
  echo "📦 Installing: ${missing[*]}"
  sudo dnf install -y --setopt=install_weak_deps=False "${missing[@]}"
}

# ---------------------------------------------------------------------------
# Version pinning
# ---------------------------------------------------------------------------
# Installed Hyprland release tag, e.g. "v0.56.2" (from `Hyprland --version`).
installed_hyprland_tag() {
  Hyprland --version 2>/dev/null | sed -n 's/^Tag:[[:space:]]*\([^,[:space:]]*\).*/\1/p' | head -n1
}

# Resolve the hyprexpo git rev to install. Sets RESOLVED_REV.
#  - HYPREXPO_REV set: validated against the installed Hyprland tag, no network.
#  - HYPREXPO_REV empty: auto-resolve the newest hyprexpo tag matching the
#    installed Hyprland version (tags follow "v<version>[+N]"), via ls-remote.
RESOLVED_REV=""
resolve_hyprexpo_rev() {
  local hl_tag hl_ver
  hl_tag="$(installed_hyprland_tag)"
  [[ -n "$hl_tag" ]] || die "Could not parse the installed Hyprland tag (Hyprland --version)."
  hl_ver="${hl_tag#v}"

  if [[ -n "$HYPREXPO_REV" ]]; then
    if [[ "$HYPREXPO_REV" == "v${hl_ver}" || "$HYPREXPO_REV" == "v${hl_ver}+"* || "$HYPREXPO_REV" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
      RESOLVED_REV="$HYPREXPO_REV"
      echo "📌 Using pinned hyprexpo rev: $RESOLVED_REV (Hyprland $hl_tag)"
      return 0
    fi
    die "HYPREXPO_REV='$HYPREXPO_REV' does not match installed Hyprland $hl_tag (tags look like 'v${hl_ver}' or 'v${hl_ver}+N'). Fix versions.env or your Hyprland version."
  fi

  echo "🔎 Auto-resolving newest hyprexpo tag for Hyprland $hl_tag..."
  local tag
  tag="$(git ls-remote --tags --refs "$PLUGIN_URL" 2>/dev/null \
    | awk -F/ '{print $NF}' \
    | grep -E "^v${hl_ver//./\\.}([+][0-9]+)?$" \
    | sort -Vu \
    | tail -n1)" || true
  [[ -n "$tag" ]] || die "No hyprexpo release tag found for Hyprland $hl_tag. Either wait for sandwichfarm/hyprexpo to cut a release, or set HYPREXPO_REV in versions.env to a known-good commit (at your own risk)."
  RESOLVED_REV="$tag"
  echo "✅ Matched hyprexpo tag: $RESOLVED_REV"
}

# Remove the given packages, but never one that another installed package still
# requires (checked by name AND by every provided capability, so pkgconfig()
# style devel dependencies are respected). Transitive deps are handled by dnf.
safe_remove_pkgs() {
  local -a targets=("$@")
  local -a removable=()
  local p cap requirer keep
  for p in "${targets[@]}"; do
    pkg_installed "$p" || continue
    keep=0
    while IFS= read -r cap; do
      [[ -z "$cap" ]] && continue
      while IFS= read -r requirer; do
        [[ -z "$requirer" ]] && continue
        [[ "$requirer" == "$p" ]] && continue
        if ! is_in_list "$requirer" "${targets[@]}"; then
          keep=1
        fi
      done < <(rpm -q --whatrequires "$cap" --qf '%{NAME}\n' 2>/dev/null || true)
      (( keep == 1 )) && break
    done < <( { rpm -q "$p" --qf '[%{PROVIDENAME}\n]' 2>/dev/null || true; echo "$p"; } | sort -u )
    if (( keep == 0 )); then
      removable+=("$p")
    else
      warn "Keeping $p (still required by another installed package)."
    fi
  done
  if (( ${#removable[@]} == 0 )); then
    echo "🔎 Nothing to remove."
    return 0
  fi
  echo "🗑️  Removing build-only packages: ${removable[*]}"
  sudo dnf remove -y --setopt=clean_requirements_on_remove=True "${removable[@]}"
}

snapshot_pkgs() {
  rpm -qa --qf '%{NAME}\n' | sort -u > "$1"
}

save_state() {
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$@" | sort -u > "$STATE_FILE"
}

load_state() {
  [[ -f "$STATE_FILE" ]] || return 0
  grep -v '^[[:space:]]*$' "$STATE_FILE" || true
}

# ---------------------------------------------------------------------------
# hyprpm wrappers
# ---------------------------------------------------------------------------
plugin_present() {
  hyprpm list 2>/dev/null | grep -qi "$PLUGIN_NAME"
}

hyprpm_add() {
  if plugin_present; then
    if (( FORCE == 0 )); then
      echo "✅ Plugin repository already present; skipping add (use --force to rebuild)."
      return 0
    fi
    echo "♻️  Removing existing plugin repository for a clean rebuild..."
    hyprpm remove "$PLUGIN_NAME" || hyprpm remove "$PLUGIN_URL" || true
  fi
  echo "🔗 Adding plugin repository: $PLUGIN_URL @ $RESOLVED_REV"
  hyprpm add "$PLUGIN_URL" "$RESOLVED_REV"
}

hyprpm_enable() {
  echo "✅ Enabling plugin: $PLUGIN_NAME"
  if ! hyprpm enable "$PLUGIN_NAME"; then
    warn "'hyprpm enable $PLUGIN_NAME' failed (it may already be enabled)."
  fi
}

hyprpm_reload() {
  echo "🔄 Reloading hyprpm state..."
  hyprpm reload || warn "hyprpm reload reported an issue."
}

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
verify_plugin() {
  local ok=1 so
  if ! in_hyprland_session; then
    warn "Not inside a Hyprland session (HYPRLAND_INSTANCE_SIGNATURE unset); skipping load checks."
    return 0
  fi
  if hyprctl plugin list 2>/dev/null | grep -qi "$PLUGIN_NAME"; then
    echo "  ✅ plugin loaded: $PLUGIN_NAME"
  else
    echo "  ❌ plugin NOT shown by 'hyprctl plugin list'"
    ok=0
  fi
  so="$(find "${HOME}/.local/share/hyprpm" -name "${PLUGIN_NAME}.so" 2>/dev/null | head -n1 || true)"
  if [[ -n "$so" ]]; then
    if ldd "$so" 2>/dev/null | grep -q 'not found'; then
      echo "  ❌ $so has missing shared libraries:"
      ldd "$so" | grep 'not found' || true
      ok=0
    else
      echo "  ✅ shared libraries resolve: $so"
    fi
  else
    warn "could not locate ${PLUGIN_NAME}.so under ~/.local/share/hyprpm"
    ok=0
  fi
  return $(( ok == 1 ? 0 : 1 ))
}

# Packages that provide a shared library the built plugin links against.
plugin_runtime_pkgs() {
  local so lib
  so="$(find "${HOME}/.local/share/hyprpm" -name "${PLUGIN_NAME}.so" 2>/dev/null | head -n1 || true)"
  [[ -n "$so" ]] || return 0
  while IFS= read -r lib; do
    rpm -qf --qf '%{NAME}\n' "$lib" 2>/dev/null || true
  done < <(ldd "$so" 2>/dev/null | grep -oE '/[^ ]+\.so[^ ]*') | sort -u
}

protect_plugin_runtime() {
  local -a pkgs=()
  mapfile -t pkgs < <(plugin_runtime_pkgs)
  if (( ${#pkgs[@]} > 0 )); then
    RUNTIME+=("${pkgs[@]}")
    echo "🔒 Protecting runtime lib providers: ${pkgs[*]}"
  fi
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
cleanup_deps() {
  local -a recorded=() filtered=() p
  mapfile -t recorded < <(load_state)
  for p in "${recorded[@]}"; do
    [[ -n "$p" ]] || continue
    is_in_list "$p" "${RUNTIME[@]}" "${KEEP_BASE[@]}" && continue
    filtered+=("$p")
  done
  # Also drop the meta package; dnf then removes any of its dependencies that
  # are no longer needed (clean_requirements_on_remove).
  if pkg_installed hyprland-devel && ! is_in_list hyprland-devel "${filtered[@]}"; then
    filtered+=("hyprland-devel")
  fi
  if (( ${#filtered[@]} == 0 )); then
    echo "🔎 No recorded build-only packages to remove."
    return 0
  fi
  safe_remove_pkgs "${filtered[@]}"
  rm -f -- "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
do_install() {
  require_hyprpm
  TMP_DIR="$(mktemp -d /tmp/hypr_plugins.XXXXXX)"
  snapshot_pkgs "$TMP_DIR/pre.txt"

  echo "📦 Ensuring build toolchain..."
  install_pkgs "${KEEP_BASE[@]}"

  echo "📦 Installing hyprpm build dependencies (${DEP_META[*]})..."
  install_pkgs "${DEP_META[@]}"

  local c
  for c in cmake cpio pkg-config git g++ gcc; do
    command -v "$c" >/dev/null 2>&1 || die "Required build tool '$c' is still missing after install."
  done

  echo "🧩 Installing/updating Hyprland headers (hyprpm update)..."
  hyprpm update

  resolve_hyprexpo_rev
  hyprpm_add
  hyprpm_enable
  hyprpm_reload

  echo "🔎 Verifying plugin..."
  verify_plugin || warn "Plugin verification reported problems; inspect 'hyprctl plugin list' / 'hyprctl configerrors'."

  rpm -qa --qf '%{NAME}\n' | sort -u > "$TMP_DIR/post.txt"
  local -a newpkgs=() merged=()
  mapfile -t newpkgs < <(comm -13 "$TMP_DIR/pre.txt" "$TMP_DIR/post.txt")
  # Merge with any previously recorded packages (e.g. a prior aborted run) so
  # nothing is lost if the state file already exists.
  mapfile -t merged < <( { load_state; (( ${#newpkgs[@]} > 0 )) && printf '%s\n' "${newpkgs[@]}"; } | sed '/^[[:space:]]*$/d' | sort -u )
  if (( ${#merged[@]} > 0 )); then
    save_state "${merged[@]}"
  fi

  protect_plugin_runtime

  if (( KEEP_DEPS == 1 )); then
    echo "⏭️  --keep-deps set: leaving build dependencies installed."
  else
    echo "🧹 Cleaning up build-only dependencies..."
    cleanup_deps
    if in_hyprland_session; then
      echo "🔎 Re-checking plugin after cleanup..."
      hyprctl plugin list 2>/dev/null | grep -qi "$PLUGIN_NAME" \
        && echo "  ✅ plugin still loaded" \
        || warn "plugin no longer listed after cleanup; rerun --install."
    fi
  fi

  echo
  echo "🎉 Plugin '$PLUGIN_NAME' installed from $PLUGIN_URL"
  echo "👉 Add this bind to ~/.config/hypr/hyprland.lua:"
  echo
  echo '    hl.bind("SUPER + G", function()'
  echo '        hl.plugin.hyprexpo.expo("toggle")'
  echo '    end)'
  echo
  echo "👉 Then reload your config (hyprctl reload) and press Super + G."
}

do_update() {
  TMP_DIR="$(mktemp -d /tmp/hypr_plugins.XXXXXX)"
  rpm -qa --qf '%{NAME}\n' | sort -u > "$TMP_DIR/pre.txt"

  echo "📦 Ensuring build dependencies (${DEP_META[*]})..."
  install_pkgs "${KEEP_BASE[@]}"
  install_pkgs "${DEP_META[@]}"

  echo "🔄 Updating all plugins..."
  hyprpm update
  hyprpm_reload

  echo "🔎 Verifying plugin..."
  verify_plugin || warn "Plugin verification reported problems after update."

  rpm -qa --qf '%{NAME}\n' | sort -u > "$TMP_DIR/post.txt"
  local -a newpkgs=()
  mapfile -t newpkgs < <(comm -13 "$TMP_DIR/pre.txt" "$TMP_DIR/post.txt")
  if (( ${#newpkgs[@]} > 0 )); then
    # Merge with any previously recorded packages.
    local -a merged=()
    mapfile -t merged < <( { load_state; printf '%s\n' "${newpkgs[@]}"; } | sort -u )
    save_state "${merged[@]}"
  fi

  if (( KEEP_DEPS == 1 )); then
    echo "⏭️  --keep-deps set: leaving build dependencies installed."
  else
    protect_plugin_runtime
    cleanup_deps
  fi
}

do_cleanup() {
  echo "🧹 Removing build-only dependencies..."
  cleanup_deps
  if in_hyprland_session; then
    if hyprctl plugin list 2>/dev/null | grep -qi "$PLUGIN_NAME"; then
      echo "  ✅ plugin still loaded"
    else
      warn "plugin not listed after cleanup."
    fi
  fi
}

do_uninstall() {
  echo "This will disable and remove the plugin '$PLUGIN_NAME', then remove the"
  echo "build-only dependencies recorded from the last install."
  echo "Your hyprland.lua bind (if any) is NOT touched."
  echo
  local ans
  read -r -p "❓ Are you sure you want to uninstall $PLUGIN_NAME? [y/N] " ans
  if [[ ! "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "❌ Uninstall cancelled by user."
    exit 0
  fi

  echo "🚫 Disabling plugin..."
  hyprpm disable "$PLUGIN_NAME" || warn "disable reported an issue (already disabled?)."
  echo "🗑️  Removing plugin repository..."
  hyprpm remove "$PLUGIN_NAME" || hyprpm remove "$PLUGIN_URL" || warn "remove reported an issue."
  hyprpm_reload || true

  cleanup_deps

  echo "🎉 '$PLUGIN_NAME' uninstalled."
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
ORIG_ARGS=("$@")
MODE=""

while (( $# )); do
  case "$1" in
    --install|--update|--cleanup|--uninstall) MODE="${1#--}" ;;
    --force)     FORCE=1 ;;
    --keep-deps) KEEP_DEPS=1 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "❌ Invalid flag: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ -z "$MODE" ]]; then
  usage
  exit 1
fi

require_user
require_hyprpm

case "$MODE" in
  install)   do_install ;;
  update)    do_update ;;
  cleanup)   cleanup_deps ;;
  uninstall) do_uninstall ;;
esac
