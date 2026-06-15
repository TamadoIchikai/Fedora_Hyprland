#!/usr/bin/env bash
set -euo pipefail

sudo dnf install -y \
thunar thunar-archive-plugin thunar-volman \
gvfs gvfs-fuse udisks2 gvfs-smb \
tumbler \
xarchiver file-roller unzip p7zip p7zip-plugins unrar \
dconf gsettings-desktop-schemas \
papirus-icon-theme adw-gtk3-theme \
shared-mime-info xdg-utils desktop-file-utils \
evince-thumbnailer ffmpegthumbnailer \
polkit mate-polkit \
xdg-desktop-portal xdg-desktop-portal-gtk

# Ensure the GVfs daemon is not masked (common issue in minimal installs)
systemctl --user unmask gvfs-daemon.service gvfs-metadata-service.service

# Define directories and files
XFCE_CONFIG_DIR="$HOME/.config/xfce4"
HELPERS_DIR="$HOME/.local/share/xfce4/helpers"
HELPERS_RC="$XFCE_CONFIG_DIR/helpers.rc"
DESKTOP_FILE="$HELPERS_DIR/foot.desktop"

echo "Creating XFCE config directory..."
mkdir -p "$XFCE_CONFIG_DIR"

echo "Generating helpers.rc configuration..."
cat << 'EOF' > "$HELPERS_RC"
TerminalEmulator=foot
TerminalEmulatorDismissed=true
EOF

echo "Creating XFCE helpers directory..."
mkdir -p "$HELPERS_DIR"

echo "Generating foot.desktop helper file..."
cat << 'EOF' > "$DESKTOP_FILE"
[Desktop Entry]
Version=1.0
Icon=foot
Type=X-XFCE-Helper
Name=Foot
StartupNotify=false
X-XFCE-Binaries=foot;
X-XFCE-Category=TerminalEmulator
X-XFCE-Commands=foot;
X-XFCE-CommandsWithParameter=foot -e "%s";
EOF

echo "Creating xterm symlink to foot (you may be prompted for your password)..."
# Using -sf to force overwrite if it already exists
sudo ln -sf $(which foot) /usr/local/bin/xterm

sleep 1
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'
sleep 1

xdg-mime default swayimg.desktop image/jpeg
xdg-mime default swayimg.desktop image/png
xdg-mime default swayimg.desktop image/gif
xdg-mime default swayimg.desktop image/webp
xdg-mime default swayimg.desktop image/svg+xml
xdg-mime default swayimg.desktop image/avif
xdg-mime default swayimg.desktop image/avifs

xdg-mime default vlc.desktop video/mpeg
xdg-mime default vlc.desktop video/ogg
xdg-mime default vlc.desktop video/webm
xdg-mime default vlc.desktop video/mp4

xdg-mime default vlc.desktop audio/mpeg        
xdg-mime default vlc.desktop audio/mp4         
xdg-mime default vlc.desktop audio/ogg

xdg-mime default code.desktop text/plain
xdg-mime default code.desktop text/x-python
xdg-mime default code.desktop text/x-c
xdg-mime default code.desktop text/x-c++src
xdg-mime default code.desktop text/html
xdg-mime default code.desktop text/css
xdg-mime default code.desktop application/javascript
xdg-mime default code.desktop application/json
xdg-mime default code.desktop text/markdown
xdg-mime default code.desktop application/x-shellscript
xdg-mime default code.desktop text/yaml
xdg-mime default code.desktop application/xml

xdg-mime default thunar.desktop inode/directory

xdg-mime default zen.desktop x-scheme-handler/http
xdg-mime default zen.desktop x-scheme-handler/https
xdg-mime default zen.desktop text/html
xdg-mime default zen.desktop application/xhtml+xml

sudo update-desktop-database
sudo update-mime-database /usr/share/mime
