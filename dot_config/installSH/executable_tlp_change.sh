#!/usr/bin/env bash

set -euo pipefail

CONF="/etc/tlp.conf"
START_VAL=75
STOP_VAL=80

echo "=== TLP Battery Threshold Setup ==="

# --- 1. Ensure TLP exists ---
if ! command -v tlp-stat >/dev/null 2>&1; then
    echo "[INFO] TLP not found. Installing..."
    if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y tlp
        sudo systemctl enable tlp --now
    else
        echo "[ERROR] dnf not available. Install TLP manually."
        exit 1
    fi
fi

# --- 2. Detect battery ---
echo "[INFO] Detecting battery..."

if ! OUTPUT=$(sudo tlp-stat -b 2>/dev/null); then
    echo "[ERROR] Failed to run tlp-stat"
    exit 1
fi

BAT=$(echo "$OUTPUT" | sed -n 's/.*Battery Status: \(BAT[0-9]\+\).*/\1/p')

if [[ -z "$BAT" ]]; then
    echo "[ERROR] Battery not detected"
    exit 1
fi

echo "[INFO] Detected battery: $BAT"

# --- 3. Backup config (safe) ---
echo "[INFO] Backing up config..."
sudo cp -n "$CONF" "${CONF}.bak" 2>/dev/null || true

# --- 4. Update /etc/tlp.conf ---
echo "[INFO] Updating $CONF ..."

sudo sed -i '/^#\?START_CHARGE_THRESH_BAT[0-9]\+=/d' "$CONF"
sudo sed -i '/^#\?STOP_CHARGE_THRESH_BAT[0-9]\+=/d' "$CONF"

printf "START_CHARGE_THRESH_%s=%s\n" "$BAT" "$START_VAL" | sudo tee -a "$CONF" >/dev/null
printf "STOP_CHARGE_THRESH_%s=%s\n" "$BAT" "$STOP_VAL" | sudo tee -a "$CONF" >/dev/null

# --- 5. Apply settings ---
echo "[INFO] Applying TLP settings..."
sudo systemctl restart tlp
sudo tlp setcharge || true

# --- 6. Configure systemd override ---
echo "[INFO] Configuring systemd override..."

OVERRIDE_DIR="/etc/systemd/system/tlp.service.d"
OVERRIDE_FILE="$OVERRIDE_DIR/override.conf"

sudo mkdir -p "$OVERRIDE_DIR"

sudo tee "$OVERRIDE_FILE" >/dev/null <<EOF
[Service]
ExecStartPost=/usr/bin/bash -c '/usr/bin/tlp setcharge || true'
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart tlp

echo "[INFO] Systemd override applied."

# --- 7. Final status ---
echo
echo "=== Final TLP Status ==="

if ! FINAL_OUTPUT=$(sudo tlp-stat -b 2>/dev/null); then
    echo "[ERROR] Failed to get final status"
    exit 1
fi

echo "$FINAL_OUTPUT"
