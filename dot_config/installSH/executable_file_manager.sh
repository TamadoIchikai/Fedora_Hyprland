#!/usr/bin/env bash
set -euo pipefail

sudo dnf install -y \
thunar thunar-archive-plugin thunar-volman \
gvfs gvfs-fuse udisks2 gvfs-smb gvfs-mtp \
peazip-qt6 unzip unrar 7zip \
dconf gsettings-desktop-schemas \
papirus-icon-theme adw-gtk3-theme \
shared-mime-info xdg-utils desktop-file-utils \
evince-thumbnailer ffmpegthumbnailer f3d \
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

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/thumbnailers" "$HOME/.local/share/mime/packages"

# STL/STEP thumbnails come from f3d. Its stock thumbnailers fail under tumbler
# (X/DRI3 connection breaks), so override them with offscreen EGL rendering.
# Same file names in ~/.local/share/thumbnailers take priority over /usr/share/thumbnailers.
echo "Setting up f3d (STL/STEP) thumbnailers with EGL backend..."
for p in native occt; do
    sed 's/^Exec=f3d /Exec=f3d --rendering-backend=egl /' \
        "/usr/share/thumbnailers/f3d-plugin-$p.thumbnailer" \
        > "$HOME/.local/share/thumbnailers/f3d-plugin-$p.thumbnailer"
done

echo "Setting up FreeCAD (.FCStd) thumbnailer..."

cat << 'EOF' > "$HOME/.local/bin/fcstd-thumbnailer"
#!/bin/sh
# Usage: fcstd-thumbnailer <size> <input.FCStd> <output.png>
unzip -p "$2" thumbnails/Thumbnail.png > "$3" && [ -s "$3" ]
EOF
chmod +x "$HOME/.local/bin/fcstd-thumbnailer"

# Unquoted heredoc so $HOME expands (tumbler needs an absolute path)
cat << EOF > "$HOME/.local/share/thumbnailers/fcstd.thumbnailer"
[Thumbnailer Entry]
TryExec=unzip
Exec=$HOME/.local/bin/fcstd-thumbnailer %s %i %o
MimeType=application/x-extension-fcstd;
EOF

cat << 'EOF' > "$HOME/.local/share/mime/packages/freecad.xml"
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-extension-fcstd">
    <comment>FreeCAD document</comment>
    <sub-class-of type="application/zip"/>
    <glob pattern="*.FCStd" case-sensitive="false"/>
  </mime-type>
</mime-info>
EOF
update-mime-database "$HOME/.local/share/mime"

# Have Thunar always request thumbnails
xfconf-query -c thunar -p /misc-thumbnail-mode -n -t string -s THUNAR_THUMBNAIL_MODE_ALWAYS || true

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

xdg-mime default dev.zed.Zed.desktop text/plain
xdg-mime default dev.zed.Zed.desktop text/x-python
xdg-mime default dev.zed.Zed.desktop text/x-c
xdg-mime default dev.zed.Zed.desktop text/x-c++src
xdg-mime default dev.zed.Zed.desktop text/html
xdg-mime default dev.zed.Zed.desktop text/css
xdg-mime default dev.zed.Zed.desktop application/javascript
xdg-mime default dev.zed.Zed.desktop application/json
xdg-mime default dev.zed.Zed.desktop text/markdown
xdg-mime default dev.zed.Zed.desktop application/x-shellscript
xdg-mime default dev.zed.Zed.desktop text/yaml
xdg-mime default dev.zed.Zed.desktop application/xml

xdg-mime default thunar.desktop inode/directory

xdg-mime default zen.desktop x-scheme-handler/http
xdg-mime default zen.desktop x-scheme-handler/https
xdg-mime default zen.desktop text/html
xdg-mime default zen.desktop application/xhtml+xml

sudo update-desktop-database
sudo update-mime-database /usr/share/mime

# Have tumbler pick up the new thumbnailers and drop cached failures
rm -rf "$HOME/.cache/thumbnails/fail"
pkill -x tumblerd || true
thunar -q 2>/dev/null || true
