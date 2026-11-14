#!/usr/bin/env bash
#
# work_related.sh - one-shot personal setup for the company training server
# (Ubuntu 24.04, sudo available). Self-contained: does NOT source lib/.
#
#   * apt:            zsh git curl duf gdu trash-cli ripgrep ...
#   * ~/.local/bin:   fzf zoxide lazygit nvim chezmoi (latest GitHub releases;
#                     apt's fzf 0.44 lacks `fzf --zsh`, lazygit isn't in apt)
#   * chezmoi:        SPARSE clone of the dotfiles repo - only the paths in
#                     SPARSE_PATHS are fetched/applied, never the whole repo
#   * shell:          ~/.zshenv PATH glue + zsh as login shell
#
# First run on the server:
#   curl -fsSL https://raw.githubusercontent.com/TamadoIchikai/Fedora_Hyprland/main/dot_config/installSH/executable_work_related.sh | bash
# Later (update everything):
#   ~/.config/installSH/work_related.sh
#
# Optional: export GITHUB_TOKEN=... to avoid GitHub API rate limits.

set -euo pipefail

# ---------------------------------------------------------------- config ----
DOTFILES_REPO="https://github.com/TamadoIchikai/Fedora_Hyprland.git"
DOTFILES_BRANCH="main"
CHEZMOI_SRC="$HOME/.local/share/chezmoi"

# chezmoi source paths to check out (git sparse-checkout, no-cone patterns).
# Add a line here to bring another config to the server.
SPARSE_PATHS=(
    "/dot_zshrc"
    "/dot_config/nvim/"
    "/dot_config/lazygit/"
    "/dot_config/installSH/executable_work_related.sh"
)

APT_PACKAGES=(zsh git curl ca-certificates tar gzip unzip duf gdu trash-cli ripgrep)

BIN_DIR="$HOME/.local/bin"
OPT_DIR="$HOME/.local/opt"

# --------------------------------------------------------------- helpers ----
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${CYAN}➡️  $*${NC}"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}" >&2; }
die()  { echo -e "${RED}❌ $*${NC}" >&2; exit 1; }

TMP_DIR="$(mktemp -d /tmp/work_related.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CURL_AUTH=()
if [[ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]]; then
    CURL_AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN:-$GH_TOKEN}")
fi

# gh_latest_json owner/repo -> prints the releases/latest JSON
gh_latest_json() {
    curl -fsSL "${CURL_AUTH[@]}" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$1/releases/latest"
}

# gh_asset_url <json> <regex> -> first browser_download_url whose file name
# matches <regex> (case-insensitive, anchored at the end by the caller).
gh_asset_url() {
    grep -Eo '"browser_download_url": *"[^"]+"' <<<"$1" \
        | sed -E 's/.*"(https[^"]+)"/\1/' \
        | grep -Ei "/$2" | head -n1
}

gh_tag() {
    grep -Eo '"tag_name": *"[^"]+"' <<<"$1" | head -n1 | sed -E 's/.*"([^"]+)"$/\1/'
}

# install_gh_release <owner/repo> <asset-regex> <binary> <version-cmd...>
# Downloads the latest release tarball, installs <binary> into BIN_DIR.
# Skipped when `<version-cmd>` output already contains the release version.
install_gh_release() {
    local repo="$1" pattern="$2" bin="$3"; shift 3
    local json tag ver url work current=""

    json="$(gh_latest_json "$repo")" || { warn "$bin: GitHub API request failed (rate limit? set GITHUB_TOKEN)"; return 1; }
    tag="$(gh_tag "$json")"; ver="${tag#v}"
    [[ -n "$ver" ]] || { warn "$bin: could not read latest tag"; return 1; }

    if [[ -x "$BIN_DIR/$bin" ]]; then
        current="$("$@" 2>/dev/null | head -n1 || true)"
        if [[ "$current" == *"$ver"* ]]; then
            ok "$bin $ver already up to date"
            return 0
        fi
    fi

    url="$(gh_asset_url "$json" "$pattern")"
    [[ -n "$url" ]] || { warn "$bin: no asset matching '$pattern' in $repo $tag"; return 1; }

    info "Installing $bin $ver"
    work="$TMP_DIR/$bin"; mkdir -p "$work"
    curl -fsSL "$url" -o "$work/pkg.tar.gz"
    tar -xzf "$work/pkg.tar.gz" -C "$work"

    if [[ "$bin" == "nvim" ]]; then
        # Full runtime tree: keep it under ~/.local/opt/nvim, symlink the binary.
        local root
        root="$(find "$work" -mindepth 1 -maxdepth 1 -type d -name 'nvim-*' | head -n1)"
        [[ -n "$root" ]] || { warn "nvim: unexpected archive layout"; return 1; }
        rm -rf "$OPT_DIR/nvim"
        mv "$root" "$OPT_DIR/nvim"
        ln -sfn "$OPT_DIR/nvim/bin/nvim" "$BIN_DIR/nvim"
    else
        local found
        found="$(find "$work" -type f -name "$bin" -perm -u+x | head -n1)"
        [[ -n "$found" ]] || found="$(find "$work" -type f -name "$bin" | head -n1)"
        [[ -n "$found" ]] || { warn "$bin: binary not found in archive"; return 1; }
        install -m 0755 "$found" "$BIN_DIR/$bin"
    fi
    ok "$bin $ver installed"
}

# ------------------------------------------------------------- preflight ----
[[ $EUID -ne 0 ]] || die "Run as your normal user (the script uses sudo where needed)."

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || warn "This script targets Ubuntu; detected '${ID:-unknown}'."
    [[ "${VERSION_ID:-}" == "24.04" ]] || warn "Tested on Ubuntu 24.04; detected '${VERSION_ID:-unknown}'."
fi

case "$(uname -m)" in
    x86_64)        ARCH_GO=amd64; ARCH_RUST=x86_64;  ARCH_LG=x86_64; ARCH_NVIM=x86_64 ;;
    aarch64|arm64) ARCH_GO=arm64; ARCH_RUST=aarch64; ARCH_LG=arm64;  ARCH_NVIM=arm64 ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
esac

mkdir -p "$BIN_DIR" "$OPT_DIR"
export PATH="$BIN_DIR:$PATH"

info "Asking for sudo once up front"
sudo -v

# ------------------------------------------------------------------- apt ----
info "Installing apt packages: ${APT_PACKAGES[*]}"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${APT_PACKAGES[@]}"
ok "apt packages installed"

# --------------------------------------------------- GitHub-release tools ----
FAILED=()
install_gh_release junegunn/fzf \
    "fzf-[0-9.]+-linux_${ARCH_GO}\.tar\.gz$" fzf \
    "$BIN_DIR/fzf" --version || FAILED+=(fzf)
install_gh_release ajeetdsouza/zoxide \
    "zoxide-[0-9.]+-${ARCH_RUST}-unknown-linux-musl\.tar\.gz$" zoxide \
    "$BIN_DIR/zoxide" --version || FAILED+=(zoxide)
install_gh_release jesseduffield/lazygit \
    "lazygit_[0-9.]+_linux_${ARCH_LG}\.tar\.gz$" lazygit \
    "$BIN_DIR/lazygit" --version || FAILED+=(lazygit)
install_gh_release neovim/neovim \
    "nvim-linux-${ARCH_NVIM}\.tar\.gz$" nvim \
    "$BIN_DIR/nvim" --version || FAILED+=(nvim)

if command -v chezmoi >/dev/null 2>&1; then
    ok "chezmoi already installed ($(chezmoi --version | awk '{print $3}' | tr -d ,))"
else
    info "Installing chezmoi"
    sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$BIN_DIR" >/dev/null
    ok "chezmoi installed"
fi

# ------------------------------------------- chezmoi (sparse source tree) ----
if [[ -d "$CHEZMOI_SRC/.git" ]]; then
    info "Updating sparse chezmoi source in $CHEZMOI_SRC"
    git -C "$CHEZMOI_SRC" sparse-checkout set --no-cone "${SPARSE_PATHS[@]}"
    git -C "$CHEZMOI_SRC" pull --ff-only --quiet || warn "git pull failed (local changes?) - applying current checkout"
else
    [[ ! -e "$CHEZMOI_SRC" ]] || die "$CHEZMOI_SRC exists but is not a git repo - move it away first."
    info "Cloning only the needed configs (sparse) into $CHEZMOI_SRC"
    git clone --quiet --depth 1 --filter=blob:none --no-checkout \
        --branch "$DOTFILES_BRANCH" "$DOTFILES_REPO" "$CHEZMOI_SRC"
    git -C "$CHEZMOI_SRC" sparse-checkout set --no-cone "${SPARSE_PATHS[@]}"
    git -C "$CHEZMOI_SRC" checkout --quiet "$DOTFILES_BRANCH"
fi

# Back up pre-existing target files that chezmoi would overwrite.
STAMP="$(date +%Y%m%d-%H%M%S)"
while IFS= read -r target; do
    [[ -f "$target" && ! -L "$target" ]] || continue
    if ! chezmoi verify "$target" >/dev/null 2>&1; then
        cp -a "$target" "$target.pre-chezmoi.$STAMP"
        warn "Backed up existing $target -> $target.pre-chezmoi.$STAMP"
    fi
done < <(chezmoi managed --include=files --path-style=absolute)

info "Applying configs with chezmoi"
chezmoi apply --force
ok "chezmoi applied:"
chezmoi managed --include=files | sed 's/^/     ~\//'

# -------------------------------------------------------- shell PATH glue ----
# .zprofile is not synced to the server (desktop-only env), so make sure zsh
# finds ~/.local/bin before .zshrc runs `fzf --zsh` / `zoxide init`.
ZSHENV="$HOME/.zshenv"
if ! grep -q '>>> work_related.sh >>>' "$ZSHENV" 2>/dev/null; then
    cat >>"$ZSHENV" <<'EOF'
# >>> work_related.sh >>>
typeset -U path PATH
path=("$HOME/.local/bin" $path)
export EDITOR=nvim
# <<< work_related.sh <<<
EOF
    ok "Added ~/.local/bin to PATH in ~/.zshenv"
fi

# ------------------------------------------------------------ login shell ----
ZSH_BIN="$(command -v zsh)"
LOGIN_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
if [[ "$LOGIN_SHELL" == "$ZSH_BIN" || "$LOGIN_SHELL" == */zsh ]]; then
    ok "Login shell is already zsh"
elif sudo chsh -s "$ZSH_BIN" "$USER" 2>/dev/null; then
    ok "Login shell changed to $ZSH_BIN (takes effect on next login)"
else
    warn "Could not change login shell (LDAP/SSSD account?). Fallback - add to ~/.bashrc:"
    echo '    [[ $- == *i* && -z "${ZSH_VERSION:-}" ]] && command -v zsh >/dev/null && exec zsh -l'
fi

# ---------------------------------------------------------------- summary ----
echo
info "Versions"
printf '   %-9s %s\n' \
    fzf     "$(fzf --version 2>/dev/null | awk '{print $1}')" \
    zoxide  "$(zoxide --version 2>/dev/null | awk '{print $2}')" \
    lazygit "$(lazygit --version 2>/dev/null | grep -Eo 'version=[^,]+' | head -n1 | cut -d= -f2)" \
    nvim    "$(nvim --version 2>/dev/null | head -n1 | awk '{print $2}')" \
    chezmoi "$(chezmoi --version 2>/dev/null | awk '{print $3}' | tr -d ,)" \
    duf     "$(dpkg-query -W -f='${Version}' duf 2>/dev/null)" \
    gdu     "$(dpkg-query -W -f='${Version}' gdu 2>/dev/null)" \
    trash   "$(dpkg-query -W -f='${Version}' trash-cli 2>/dev/null)"

((${#FAILED[@]} == 0)) || warn "Failed: ${FAILED[*]} - re-run the script (set GITHUB_TOKEN if rate-limited)."

echo
ok "Done. Start zsh (or re-login): zinit + powerlevel10k bootstrap on first launch;"
echo "   run 'p10k configure' if the wizard doesn't start (~/.p10k.zsh is not synced)."
echo "   To push config edits from the server, switch the remote to SSH:"
echo "   chezmoi git remote set-url origin git@github.com:TamadoIchikai/Fedora_Hyprland.git"
