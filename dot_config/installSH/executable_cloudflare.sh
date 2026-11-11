#!/usr/bin/env bash
# Cloudflare WARP, off by default, toggled from Waybar via a narrow sudo rule.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

WARP_USER="$(installsh_target_user)"

# --- 1. Add Cloudflare repo + install ---
curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo \
  | sudo tee /etc/yum.repos.d/cloudflare-warp.repo >/dev/null
sudo dnf makecache
dnf_install cloudflare-warp

# --- 2. Register the device (skip if already registered) ---
# Zero Trust instead: warp-cli registration new --tok <registration-token>
if warp-cli --accept-tos registration show >/dev/null 2>&1; then
  echo "WARP device already registered. Skipping."
else
  warp-cli --accept-tos registration new
fi

# --- 3. Passwordless root rule for the Waybar toggle ---
SUDOERS_TMP="$(mktemp)"
trap 'rm -f "$SUDOERS_TMP"' EXIT
cat >"$SUDOERS_TMP" <<CONF
# Allow ${WARP_USER} to start/stop the Cloudflare WARP root daemon without a
# password so the Waybar click-toggle can run non-interactively.
${WARP_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl start warp-svc.service, /usr/bin/systemctl stop warp-svc.service
CONF
# Validate before installing so a bad rule can never lock sudo.
sudo visudo -cf "$SUDOERS_TMP"
sudo install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/warp-toggle

# --- 4. Keep WARP fully off after reboot (no background service) ---
sudo systemctl disable warp-svc.service
systemctl --user disable warp-desktop-svc.service 2>/dev/null || true
systemctl --user mask app-com.cloudflare.WarpTaskbar@autostart.service
systemctl --user mask warp-desktop-svc.service

# --- 5. Connect and verify ---
warp-cli --accept-tos connect
sleep 2
warp-cli --accept-tos status
sudo -n systemctl is-active warp-svc && echo "sudo rule OK (${WARP_USER})"
