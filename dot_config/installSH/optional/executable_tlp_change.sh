#!/usr/bin/env bash
set -euo pipefail

CONF="/etc/tlp.conf"
START_VAL=75
STOP_VAL=80

echo "=== TLP Battery Threshold Setup ==="

# --- helpers: set/replace a KEY=VALUE in tlp.conf cleanly ---
set_tlp_kv() {
    local key="$1"
    local value="$2"
    # delete any existing (commented or not) occurrences, then append one canonical line
    sudo sed -i "/^[[:space:]]*#\?[[:space:]]*${key}=.*/d" "$CONF"
    printf "%s=%s\n" "$key" "$value" | sudo tee -a "$CONF" >/dev/null
}

have_word() {
    local word="$1"
    grep -qw -- "$word"
}

# --- 0. Detect Fedora ---
IS_FEDORA=0
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" == "fedora" ]]; then
        IS_FEDORA=1
        echo "[INFO] Fedora detected"
    fi
fi

# --- 0.1 Remove conflicting services (Fedora only) ---
if [[ "$IS_FEDORA" -eq 1 ]]; then
    echo "[INFO] Removing conflicting power management services..."

    SERVICES=(
        power-profiles-daemon
        tuned
        tuned-ppd
    )

    for svc in "${SERVICES[@]}"; do
        if systemctl list-unit-files --type=service | grep -q "^${svc}.service"; then
            echo "[INFO] Disabling and masking $svc..."
            sudo systemctl stop "$svc" 2>/dev/null || true
            sudo systemctl disable "$svc" 2>/dev/null || true
            sudo systemctl mask "$svc" 2>/dev/null || true
        fi
    done

    # Optional cleanup
    if command -v dnf >/dev/null 2>&1; then
        echo "[INFO] Removing tuned packages (optional)..."
        sudo dnf remove -y tuned tuned-ppd 2>/dev/null || true
    fi
fi

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

# --- 3. Backup config ---
echo "[INFO] Backing up config..."
sudo cp -n "$CONF" "${CONF}.bak" 2>/dev/null || true

# --- 4. Update config (battery thresholds) ---
echo "[INFO] Updating $CONF (battery thresholds)..."

sudo sed -i '/^#\?START_CHARGE_THRESH_BAT[0-9]\+=/d' "$CONF"
sudo sed -i '/^#\?STOP_CHARGE_THRESH_BAT[0-9]\+=/d' "$CONF"

printf "START_CHARGE_THRESH_%s=%s\n" "$BAT" "$START_VAL" | sudo tee -a "$CONF" >/dev/null
printf "STOP_CHARGE_THRESH_%s=%s\n" "$BAT" "$STOP_VAL" | sudo tee -a "$CONF" >/dev/null

# --- 4.x CPU + GPU tuning (requested) ---
echo "[INFO] Detecting CPU governor support..."
CPU0_GOV_FILE="/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"
if [[ -r "$CPU0_GOV_FILE" ]]; then
    AVAIL_GOVS="$(tr ' ' '\n' < "$CPU0_GOV_FILE" | tr -d '\r')"
    if echo "$AVAIL_GOVS" | have_word performance && echo "$AVAIL_GOVS" | have_word powersave; then
        echo "[INFO] Governors supported: performance + powersave -> writing CPU_SCALING_GOVERNOR_*"
        set_tlp_kv "CPU_SCALING_GOVERNOR_ON_AC" "performance"
        set_tlp_kv "CPU_SCALING_GOVERNOR_ON_BAT" "powersave"
    else
        echo "[WARN] Missing required governors (need: performance and powersave). Available: $(tr '\n' ' ' <<<"$AVAIL_GOVS")"
    fi
else
    echo "[WARN] Cannot read $CPU0_GOV_FILE; skipping CPU_SCALING_GOVERNOR_*"
fi

echo "[INFO] Detecting intel_pstate..."
CPU_DRIVER_FILE="/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver"
SCALING_DRIVER=""
if [[ -r "$CPU_DRIVER_FILE" ]]; then
    SCALING_DRIVER="$(cat "$CPU_DRIVER_FILE" 2>/dev/null || true)"
fi

if [[ "$SCALING_DRIVER" == "intel_pstate" ]]; then
    echo "[INFO] intel_pstate detected -> writing CPU_ENERGY_PERF_POLICY_*"
    set_tlp_kv "CPU_ENERGY_PERF_POLICY_ON_AC" "performance"
    set_tlp_kv "CPU_ENERGY_PERF_POLICY_ON_BAT" "balance_power"
else
    echo "[WARN] intel_pstate not detected (scaling_driver='$SCALING_DRIVER'); skipping CPU_ENERGY_PERF_POLICY_*"
fi

echo "[INFO] Checking TLP platform features (tlp-stat -p) for Intel GPU..."
if PLATFORM_OUT="$(sudo tlp-stat -p 2>/dev/null)"; then
    # Heuristic match (wording differs between distros/TLP versions):
    # set Intel GPU lines only when tlp-stat -p suggests Intel GPU/i915 is present.
    if echo "$PLATFORM_OUT" | grep -Eqi 'intel.+(gpu|graphics)|i915'; then
        echo "[INFO] Intel GPU appears supported -> writing INTEL_GPU_*"
        set_tlp_kv "INTEL_GPU_MIN_FREQ_ON_AC" "0"
        set_tlp_kv "INTEL_GPU_MAX_FREQ_ON_AC" "0"
    else
        echo "[WARN] tlp-stat -p did not indicate Intel GPU support; skipping INTEL_GPU_*"
    fi
else
    echo "[WARN] Failed to run tlp-stat -p; skipping Intel GPU config"
fi

# --- 5. Apply settings ---
echo "[INFO] Applying TLP settings..."
sudo systemctl restart tlp
sudo tlp setcharge || true

# --- 6. Final status ---
echo
echo "=== Final TLP Status ==="

if ! FINAL_OUTPUT=$(sudo tlp-stat -b 2>/dev/null); then
    echo "[ERROR] Failed to get final status"
    exit 1
fi

echo "$FINAL_OUTPUT"
