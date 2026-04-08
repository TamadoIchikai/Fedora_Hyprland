#!/bin/bash
set -euo pipefail

echo "Uninstalling HyprMode and Emergency Recovery Daemon..."

# Stop and disable daemon service
echo "Stopping daemon service..."
systemctl --user stop hyprmode-daemon 2>/dev/null || true
systemctl --user disable hyprmode-daemon 2>/dev/null || true

# Remove systemd service file
echo "Removing systemd service..."
rm ~/.config/systemd/user/hyprmode-daemon.service

# Remove all installed files
echo "Removing installed files from ~/.local/bin..."
rm ~/.local/bin/hyprmode
rm ~/.local/bin/hyprmode-daemon
rm ~/.local/bin/hyprmode-daemon-wrapper

# Reload systemd
systemctl --user daemon-reload

echo ""
echo "✓ Uninstallation complete!"
echo ""
echo "Daemon service status:"
systemctl --user status hyprmode-daemon --no-pager 2>&1 | head -5
