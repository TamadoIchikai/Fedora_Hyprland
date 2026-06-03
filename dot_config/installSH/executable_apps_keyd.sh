#!/usr/bin/env bash
set -euo pipefail

# Enable command tracing only when DEBUG=1 is set:
# DEBUG=1 ./install-keyd.sh
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x
fi

REPO_URL="https://github.com/rvaiya/keyd.git"
BASE_DIR="$HOME/Downloads/Systems"
SRC_DIR="$BASE_DIR/keyd"
KEYD_CONFIG_DIR="/etc/keyd"
KEYD_CONFIG_FILE="$KEYD_CONFIG_DIR/default.conf"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

install_keyd_config_if_missing() {
    echo "==> Checking keyd config..."

    sudo mkdir -p "$KEYD_CONFIG_DIR"

    if sudo test -e "$KEYD_CONFIG_FILE"; then
        echo "==> Existing config found:"
        echo "    $KEYD_CONFIG_FILE"
        echo "==> Not overwriting existing keyd config."
        return 0
    fi

    echo "==> Creating default keyd config:"
    echo "    $KEYD_CONFIG_FILE"

    sudo tee "$KEYD_CONFIG_FILE" >/dev/null <<'EOF'
[ids]
*

[main]
capslock = esc
esc = capslock

[shift]
backspace = delete

[control+shift]
backspace = S-delete
EOF

    sudo chmod 644 "$KEYD_CONFIG_FILE"

    echo "==> keyd config created."
}

echo "==> Checking required commands..."
need_cmd git
need_cmd make
need_cmd cc
need_cmd sudo
need_cmd systemctl

echo "==> Install directory:"
echo "    $SRC_DIR"
echo

mkdir -p "$BASE_DIR"

if [[ -e "$SRC_DIR" && ! -d "$SRC_DIR/.git" ]]; then
    die "$SRC_DIR exists but is not a Git repository. Move it manually first."
fi

if [[ ! -d "$SRC_DIR/.git" ]]; then
    echo "==> Cloning keyd into $SRC_DIR..."
    git clone "$REPO_URL" "$SRC_DIR"
else
    echo "==> Existing keyd repo found. Updating it..."
    git -C "$SRC_DIR" fetch --tags origin
fi

cd "$SRC_DIR"

echo "==> Choosing latest stable tag..."
LATEST_TAG="$(
    git tag --list 'v*' --sort=-v:refname | head -n 1 || true
)"

if [[ -n "$LATEST_TAG" ]]; then
    echo "==> Checking out latest tag: $LATEST_TAG"
    git checkout "$LATEST_TAG"
else
    echo "==> No version tag found. Staying on default branch."
fi

echo
echo "==> About to build and install keyd."
echo "    Root actions will be done through sudo."
echo "    This script will NOT uninstall or delete old keyd files."
echo "    This script will NOT overwrite existing /etc/keyd/default.conf."
echo

read -r -p "Continue? [y/N] " confirm
case "$confirm" in
    y|Y|yes|YES) ;;
    *) die "Cancelled by user." ;;
esac

echo "==> Refreshing sudo permission..."
sudo -v

echo "==> Building keyd..."
make

echo "==> Installing keyd..."
sudo make install

install_keyd_config_if_missing

echo "==> Checking keyd config syntax..."
sudo keyd check

echo "==> Enabling and starting keyd service..."
sudo systemctl daemon-reload
sudo systemctl enable --now keyd

echo "==> Reloading keyd config..."
sudo keyd reload

echo "==> Checking service status..."
systemctl --no-pager --full status keyd || true

echo
echo "==> keyd installed, configured, and activated."
echo
echo "Installed config:"
echo "  $KEYD_CONFIG_FILE"
echo
echo "Useful commands:"
echo "  sudo systemctl status keyd"
echo "  sudo journalctl -eu keyd"
echo "  sudo keyd check"
echo "  sudo keyd reload"
echo "  keyd monitor"
