sudo tee /etc/systemd/system/hibernate-prepare.service >/dev/null <<'EOF'
[Unit]
Description=Swap off zram and re-enable disk swap before hibernation
Before=systemd-hibernate.service

[Service]
Type=oneshot
ExecStart=-/usr/bin/swapoff /dev/zram0
ExecStart=/usr/bin/swapoff /dev/nvme0n1p7
ExecStart=/usr/bin/swapon /dev/nvme0n1p7

[Install]
WantedBy=systemd-hibernate.service
EOF

sudo tee /etc/systemd/system/hibernate-restore.service >/dev/null <<'EOF'
[Unit]
Description=Restore zram swap after resuming from hibernation
After=systemd-hibernate.service

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c 'grep -q "^/dev/zram0 " /proc/swaps && exit 0; exec /usr/lib/systemd/system-generators/zram-generator --setup-device zram0'

[Install]
WantedBy=hibernate.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable hibernate-prepare.service hibernate-restore.service
