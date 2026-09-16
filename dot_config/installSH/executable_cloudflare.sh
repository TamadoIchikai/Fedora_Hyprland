#!/usr/bin/env bash
set -euo pipefail

# --- 1. Add Cloudflare repo ---
curl -fsSl https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | sudo tee /etc/yum.repos.d/cloudflare-warp.repo
sudo dnf update -y
sudo dnf install -y cloudflare-warp

# --- 2. Register the device (skip if already registered) ---
# Consumer:  warp-cli registration new
# Zero Trust: warp-cli registration new --tok <registration-token>
warp-cli registration new

# --- 3. Passwordless root rule for the Waybar toggle (dynamic username) ---
sudo tee /etc/sudoers.d/warp-toggle >/dev/null <<EOF
# Allow \$(whoami) to start/stop the Cloudflare WARP root daemon without a
# password so the Waybar click-toggle can run non-interactively.
\$(whoami) ALL=(root) NOPASSWD: /usr/bin/systemctl start warp-svc.service, /usr/bin/systemctl stop warp-svc.service
EOF
sudo chmod 440 /etc/sudoers.d/warp-toggle
sudo visudo -cf /etc/sudoers.d/warp-toggle

# --- 4. Keep WARP fully off after reboot (no background service) ---
sudo systemctl disable warp-svc.service
systemctl --user disable warp-desktop-svc.service

# --- 5. Connect and verify ---
warp-cli connect
sleep 2
warp-cli status
sudo -n systemctl is-active warp-svc && echo "sudo rule OK ($(whoami))"
