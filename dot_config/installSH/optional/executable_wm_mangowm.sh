#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# wm_mangowm.sh - Build & install mangowm (MangoWC) from source on Fedora
# ----------------------------------------------------------------------------
# Only mangowm itself is compiled; wlroots / scenefx / cjson come from the
# Fedora repositories as packaged dependencies.
# ============================================================================

MANGO_REPO="https://github.com/mangowm/mango.git"
MANGO_API="https://api.github.com/repos/mangowm/mango/tags?per_page=20"
PREFIX="/usr"
MANGO_VERSION=""
FORCE=0
KEEP_DEPS=0
TMP_DIR=""

# Packages already provided by the rest of installSH (kept, never removed).
KEEP_BASE=(meson ninja-build gcc gcc-c++ make git cmake pkgconf pkgconf-pkg-config)
# Runtime libraries mangowm links against (installed explicitly, kept).
RUNTIME=(wlroots scenefx cjson)
# Build-only dependencies (installed, then removed after a successful build).
BUILD_DEPS=(wayland-devel wayland-protocols-devel wlroots-devel scenefx-devel \
  libinput-devel libxkbcommon-devel pixman-devel pcre2-devel pango-devel cairo-devel \
  cjson-devel xcb-util-wm-devel libdisplay-info-devel libliftoff-devel libseat-devel)

# Files/directories installed by `ninja install` (prefix=/usr).
INSTALL_FILES=(
  /usr/bin/mango
  /usr/bin/mmsg
  /usr/bin/mangonag
  /usr/share/wayland-sessions/mango.desktop
  /usr/share/xdg-desktop-portal/mango-portals.conf
  /usr/lib/systemd/user/mango-session.target
  /usr/share/man/man1/mmsg.1
  /usr/share/man/man1/mangonag.1
)
INSTALL_DIRS=(/etc/mango)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: sudo $0 <mode> [options]

Modes (choose one):
  --install     Build & install mangowm from source (choose from the latest 3 versions)
  --update      Check GitHub for a newer version and update an existing install
  --cleanup     Remove build-only dependencies (keeps runtime libraries)
  --uninstall   Remove mangowm and every dependency this script installed

Options:
  --force       Rebuild/reinstall even if the same version is already installed
  --keep-deps   Skip the post-install dependency cleanup
  -h, --help    Show this help message
EOF
}

warn() { echo "⚠️  $*" >&2; }
die()  { echo "❌ $*" >&2; exit 1; }

cleanup_tmp() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf -- "$TMP_DIR"
}
trap cleanup_tmp EXIT

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "❌ This script must be run as root." >&2
    echo "👉 Please run again using: sudo $0 ${ORIG_ARGS[*]}" >&2
    exit 1
  fi
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
  dnf install -y "${missing[@]}"
}

# Remove the given packages, but never a package that an external (kept)
# package still depends on. transitative deps are cleaned by dnf itself.
safe_remove_pkgs() {
  local -a targets=("$@")
  local -a removable=()
  local p req requirer keep
  for p in "${targets[@]}"; do
    pkg_installed "$p" || continue
    req="$(rpm -q --whatrequires --qf '%{NAME}\n' "$p" 2>/dev/null || true)"
    keep=0
    while IFS= read -r requirer; do
      [[ -z "$requirer" ]] && continue
      if ! is_in_list "$requirer" "${targets[@]}"; then
        keep=1
      fi
    done <<< "$req"
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
  echo "🗑️  Removing: ${removable[*]}"
  dnf remove -y "${removable[@]}"
}

fetch_tags() {
  curl -fsSL -H "Accept: application/vnd.github+json" "$MANGO_API" 2>/dev/null \
    | jq -r '.[].name' | grep -E '^v?[0-9]+\.' | head -n 20
}

ver_norm() { echo "${1#v}"; }

detect_installed_version() {
  local v=""
  if [[ -x /usr/bin/mango ]] && command -v strings >/dev/null 2>&1; then
    v="$(strings /usr/bin/mango 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\([^)]*\)' | head -n1 || true)"
    [[ -n "$v" ]] && { echo "${v%%(*}"; return; }
    v="$(strings /usr/bin/mango 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
    [[ -n "$v" ]] && { echo "$v"; return; }
  fi
  echo "unknown"
}

resolve_target_home() {
  local u="${SUDO_USER:-$USER}" h=""
  h="$(getent passwd "$u" 2>/dev/null | cut -d: -f6 || true)"
  [[ -n "$h" ]] || h="${HOME:-/root}"
  echo "$h"
}

safe_rm_file() {
  local t="$1"
  if [[ "$t" != /* || "$t" == "/" || "$t" == *"/../"* || "$t" == */.. ]]; then
    die "Refusing to remove unsafe path: $t"
  fi
  if [[ -e "$t" || -L "$t" ]]; then
    rm -f -- "$t"
    echo "  ✅ removed $t"
  else
    echo "  ⏭️  not found: $t"
  fi
}

safe_rm_dir() {
  local t="$1"
  if [[ "$t" != /* || "$t" == "/" || "$t" == *"/../"* || "$t" == */.. ]]; then
    die "Refusing to remove unsafe path: $t"
  fi
  if [[ -e "$t" ]]; then
    rm -rf -- "$t"
    echo "  ✅ removed $t/"
  else
    echo "  ⏭️  not found: $t/"
  fi
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
select_version_interactive() {
  echo "🔍 Fetching available mangowm versions from GitHub..."
  local -a tags=()
  mapfile -t tags < <(fetch_tags)
  if (( ${#tags[@]} == 0 )); then
    die "Could not fetch mangowm tags from GitHub. Check your network connection."
  fi
  local n=$(( ${#tags[@]} < 3 ? ${#tags[@]} : 3 ))
  echo "Available versions:"
  local i
  for (( i=0; i<n; i++ )); do
    if (( i == 0 )); then
      echo "  $((i+1))) ${tags[$i]}  (latest)"
    else
      echo "  $((i+1))) ${tags[$i]}"
    fi
  done
  local choice
  while true; do
    read -r -p "👉 Choose a version [1-$n] (default 1): " choice
    choice="${choice:-1}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= n )); then
      MANGO_VERSION="${tags[$((choice-1))]}"
      break
    fi
    echo "❌ Invalid choice. Enter a number between 1 and $n."
  done
  echo "✅ Selected version: $MANGO_VERSION"
}

do_update_check() {
  if ! command -v mango >/dev/null 2>&1; then
    echo "⛔ mangoWC haven't installed."
    exit 1
  fi
  echo "🔍 Checking latest version from GitHub..."
  local latest current
  latest="$(fetch_tags | sed -n '1p' || true)"
  [[ -n "$latest" ]] || die "Could not fetch the latest mangowm version from GitHub."
  current="$(detect_installed_version)"
  echo "📦 Installed version: $current"
  echo "🌟 Latest version:    $latest"
  if [[ "$(ver_norm "$current")" == "$(ver_norm "$latest")" && ${FORCE} -eq 0 ]]; then
    echo "✅ You are already up to date! No action required."
    exit 0
  fi
  echo "🚀 Update available: $current -> $latest"
  local ans
  read -r -p "❓ Do you want to update now? [y/N] " ans
  if [[ ! "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "❌ Update cancelled by user."
    exit 0
  fi
  MANGO_VERSION="$latest"
}

verify_install() {
  local ok=1 c f d
  for c in mango mmsg mangonag; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "  ✅ $c -> $(command -v "$c")"
    else
      echo "  ❌ $c not found"
      ok=0
    fi
  done
  if command -v mango >/dev/null 2>&1; then
    if ldd "$(command -v mango)" 2>/dev/null | grep -q 'not found'; then
      echo "  ❌ mango has missing shared libraries:"
      ldd "$(command -v mango)" | grep 'not found' || true
      ok=0
    else
      echo "  ✅ all shared libraries resolved"
    fi
  fi
  if pkg-config --exists 'scenefx-0.5'; then
    echo "  ✅ pkgconfig scenefx-0.5 present"
  else
    warn "pkgconfig scenefx-0.5 not found"
  fi
  for f in "${INSTALL_FILES[@]}"; do
    if [[ -e "$f" ]]; then
      echo "  ✅ $f"
    else
      warn "missing: $f"
    fi
  done
  if [[ -e /usr/share/wayland-sessions/mango.desktop ]]; then
    echo "  ✅ session entry present"
  else
    echo "  ❌ session entry missing"
    ok=0
  fi
  for d in "${INSTALL_DIRS[@]}"; do
    if [[ -d "$d" ]]; then
      echo "  ✅ $d/"
    else
      echo "  ❌ $d/ missing"
      ok=0
    fi
  done
  (( ok == 1 ))
}

seed_config() {
  local home dest
  home="$(resolve_target_home)"
  dest="$home/.config/mango"
  if [[ ! -d /etc/mango ]]; then
    warn "/etc/mango not found; skipping config seeding."
    return 0
  fi
  mkdir -p "$dest"
  # Only seed config.conf (the primary config format); never config.toml.
  local src="/etc/mango/config.conf"
  if [[ ! -e "$src" ]]; then
    warn "/etc/mango/config.conf not found; skipping config seeding."
    return 0
  fi
  if [[ -e "$dest/config.conf" ]]; then
    echo "  ⏭️  kept existing $dest/config.conf"
  else
    cp -a -- "$src" "$dest/config.conf"
    echo "  ✅ seeded $dest/config.conf"
  fi
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    chown -R "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$dest" 2>/dev/null || true
  fi
}

do_install() {
  [[ -n "$MANGO_VERSION" ]] || die "No mangowm version selected."

  local current
  current="$(detect_installed_version)"
  if [[ "$(ver_norm "$current")" == "$(ver_norm "$MANGO_VERSION")" && ${FORCE} -eq 0 ]]; then
    echo "✅ mangowm $MANGO_VERSION is already installed. Use --force to reinstall."
    exit 0
  fi

  TMP_DIR="$(mktemp -d /tmp/wm_mangowm.XXXXXX)"
  rpm -qa --qf '%{NAME}\n' | sort -u > "$TMP_DIR/pre.txt"

  echo "📦 Ensuring build toolchain..."
  install_pkgs "${KEEP_BASE[@]}"
  local c
  for c in git meson ninja gcc make pkg-config; do
    command -v "$c" >/dev/null 2>&1 || die "Required build tool '$c' is missing."
  done

  echo "📦 Installing runtime libraries (${RUNTIME[*]})..."
  install_pkgs "${RUNTIME[@]}"

  echo "📦 Installing build dependencies..."
  install_pkgs "${BUILD_DEPS[@]}"

  pkg-config --exists 'wlroots-0.20' || die "pkgconfig(wlroots-0.20) not found after install."
  pkg-config --exists 'scenefx-0.5'   || die "pkgconfig(scenefx-0.5) not found after install."

  local build_root="/tmp/mangowm-build-${MANGO_VERSION}"
  local src="$build_root/src"
  local out="$build_root/build"
  echo "🔗 Cloning mangowm $MANGO_VERSION ..."
  rm -rf -- "$build_root"
  mkdir -p "$build_root"
  git clone --branch "$MANGO_VERSION" --depth 1 "$MANGO_REPO" "$src"

  echo "🔨 Building mangowm $MANGO_VERSION ..."
  meson setup "$out" "$src" -Dprefix="$PREFIX" --buildtype=release
  ninja -C "$out"

  echo "⬆️  Installing mangowm ..."
  ninja -C "$out" install

  echo "🔎 Verifying installation..."
  verify_install || die "Installation verification failed."

  seed_config

  if (( KEEP_DEPS == 0 )); then
    echo "🧹 Cleaning up build-only dependencies..."
    rpm -qa --qf '%{NAME}\n' | sort -u > "$TMP_DIR/post.txt"
    local -a newpkgs=() candidates=() p k
    mapfile -t newpkgs < <(comm -13 "$TMP_DIR/pre.txt" "$TMP_DIR/post.txt")
    for p in "${newpkgs[@]}"; do
      [[ -n "$p" ]] || continue
      if is_in_list "$p" "${RUNTIME[@]}" "${KEEP_BASE[@]}"; then
        continue
      fi
      candidates+=("$p")
    done
    if (( ${#candidates[@]} > 0 )); then
      safe_remove_pkgs "${candidates[@]}"
    else
      echo "🔎 No new packages to remove."
    fi
    echo "🔎 Verifying runtime libraries still resolve..."
    if command -v mango >/dev/null 2>&1 && ldd "$(command -v mango)" | grep -q 'not found'; then
      warn "mango now reports missing shared libraries after cleanup:"
      ldd "$(command -v mango)" | grep 'not found' || true
    else
      echo "  ✅ mango libraries still resolve"
    fi
    echo "  ✅ runtime present: $(rpm -q "${RUNTIME[@]}" 2>/dev/null | tr '\n' ' ')"
  else
    echo "⏭️  --keep-deps set: leaving build dependencies installed."
  fi

  echo
  echo "🎉 mangowm $MANGO_VERSION installed successfully!"
  echo "👉 Log out and pick 'mango' from your display manager, or run 'mango' from a TTY."
  echo "👉 Starter config placed in $(resolve_target_home)/.config/mango if it was absent."
}

do_cleanup() {
  echo "🧹 Removing build-only dependencies..."
  safe_remove_pkgs "${BUILD_DEPS[@]}"
  if command -v mango >/dev/null 2>&1; then
    if ldd "$(command -v mango)" | grep -q 'not found'; then
      warn "mango has missing shared libraries after cleanup."
    else
      echo "  ✅ mango shared libraries still resolve."
    fi
  fi
}

do_uninstall() {
  echo "This will remove:"
  local f d
  for f in "${INSTALL_FILES[@]}"; do echo "  - $f"; done
  for d in "${INSTALL_DIRS[@]}"; do echo "  - $d/"; done
  echo "And uninstall dependency packages: ${RUNTIME[*]} ${BUILD_DEPS[*]}"
  echo "Your configuration in ~/.config/mango will NOT be touched."
  echo
  local ans
  read -r -p "❓ Are you sure you want to uninstall mangowm? [y/N] " ans
  if [[ ! "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "❌ Uninstall cancelled by user."
    exit 0
  fi

  echo "🗑️  Removing mangowm files..."
  for f in "${INSTALL_FILES[@]}"; do safe_rm_file "$f"; done
  for d in "${INSTALL_DIRS[@]}"; do safe_rm_dir "$d"; done

  echo "🧹 Removing dependencies..."
  safe_remove_pkgs "${RUNTIME[@]}" "${BUILD_DEPS[@]}"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
  fi
  echo "✅ mangowm uninstalled."
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
ORIG_ARGS=("$@")
MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install|--update|--cleanup|--uninstall)
      if [[ -n "$MODE" ]]; then
        echo "❌ Only one mode may be specified." >&2
        usage
        exit 1
      fi
      MODE="${1#--}"
      shift
      ;;
    --force)     FORCE=1; shift ;;
    --keep-deps) KEEP_DEPS=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)
      echo "❌ Invalid flag: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  usage
  exit 1
fi

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$MODE" in
  install|update)
    for c in curl jq; do
      command -v "$c" >/dev/null 2>&1 || die "'$c' is required but not installed."
    done
    if [[ "$MODE" == "install" ]]; then
      select_version_interactive
    else
      do_update_check
    fi
    require_root
    do_install
    ;;
  cleanup)
    require_root
    do_cleanup
    ;;
  uninstall)
    require_root
    do_uninstall
    ;;
esac
