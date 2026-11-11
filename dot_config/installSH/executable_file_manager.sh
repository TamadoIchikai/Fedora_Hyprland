#!/usr/bin/env bash
# Thunar + thumbnailers + default applications (MIME associations).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

dnf_install \
  thunar thunar-archive-plugin thunar-volman \
  gvfs gvfs-fuse gvfs-smb gvfs-mtp udisks2 \
  peazip-qt6 unzip unrar 7zip \
  shared-mime-info xdg-utils desktop-file-utils \
  evince-thumbnailer ffmpegthumbnailer f3d \
  polkit mate-polkit \
  xdg-desktop-portal xdg-desktop-portal-gtk

# Ensure the GVfs daemon is not masked (common issue in minimal installs)
systemctl --user unmask gvfs-daemon.service gvfs-metadata-service.service

# --- Terminal integration: Thunar "Open Terminal Here" uses foot ---
XFCE_CONFIG_DIR="$HOME/.config/xfce4"
HELPERS_DIR="$HOME/.local/share/xfce4/helpers"
mkdir -p "$XFCE_CONFIG_DIR" "$HELPERS_DIR"

cat >"$XFCE_CONFIG_DIR/helpers.rc" <<'CONF'
TerminalEmulator=foot
TerminalEmulatorDismissed=true
CONF

cat >"$HELPERS_DIR/foot.desktop" <<'CONF'
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
CONF

# Apps that hard-code `xterm` get foot instead (foot comes from apps_CLI.sh).
if FOOT_BIN="$(command -v foot)"; then
  sudo ln -sf "$FOOT_BIN" /usr/local/bin/xterm
else
  warn "foot is not installed yet; skipping the xterm -> foot symlink (run apps_CLI.sh first)."
fi

# --- Thumbnailers ---
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/thumbnailers" "$HOME/.local/share/mime/packages"

# STL/STEP thumbnails come from f3d. Its stock thumbnailers fail under tumbler
# (X/DRI3 connection breaks), so override them with offscreen EGL rendering.
# Same file names in ~/.local/share/thumbnailers take priority over /usr/share/thumbnailers.
info "Setting up f3d (STL/STEP) thumbnailers with EGL backend..."
for p in native occt; do
  sed 's/^Exec=f3d /Exec=f3d --rendering-backend=egl /' \
    "/usr/share/thumbnailers/f3d-plugin-$p.thumbnailer" \
    >"$HOME/.local/share/thumbnailers/f3d-plugin-$p.thumbnailer"
done

info "Setting up FreeCAD (.FCStd) thumbnailer..."
cat >"$HOME/.local/bin/fcstd-thumbnailer" <<'CONF'
#!/bin/sh
# Usage: fcstd-thumbnailer <size> <input.FCStd> <output.png>
unzip -p "$2" thumbnails/Thumbnail.png > "$3" && [ -s "$3" ]
CONF
chmod +x "$HOME/.local/bin/fcstd-thumbnailer"

# Unquoted heredoc so $HOME expands (tumbler needs an absolute path)
cat >"$HOME/.local/share/thumbnailers/fcstd.thumbnailer" <<CONF
[Thumbnailer Entry]
TryExec=unzip
Exec=$HOME/.local/bin/fcstd-thumbnailer %s %i %o
MimeType=application/x-extension-fcstd;
CONF

cat >"$HOME/.local/share/mime/packages/freecad.xml" <<'CONF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-extension-fcstd">
    <comment>FreeCAD document</comment>
    <sub-class-of type="application/zip"/>
    <glob pattern="*.FCStd" case-sensitive="false"/>
  </mime-type>
</mime-info>
CONF
update-mime-database "$HOME/.local/share/mime"

# Have Thunar always request thumbnails
xfconf-query -c thunar -p /misc-thumbnail-mode -n -t string -s THUNAR_THUMBNAIL_MODE_ALWAYS || true

# --- Default applications ---
# set_default <desktop-file> <mime-type>...
set_default() {
  local app="$1" mime
  shift
  for mime in "$@"; do
    xdg-mime default "$app" "$mime"
  done
}

set_default swayimg.desktop \
  image/jpeg image/png image/gif image/webp image/svg+xml image/avif image/avifs
set_default mpv.desktop \
  video/mpeg video/ogg video/webm video/mp4 video/x-matroska \
  audio/mpeg audio/mp4 audio/ogg audio/flac
set_default dev.zed.Zed.desktop \
  text/plain text/x-python text/x-c text/x-c++src text/css text/markdown text/yaml \
  application/javascript application/json application/x-shellscript application/xml
set_default thunar.desktop inode/directory
set_default zen.desktop \
  x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml

sudo update-desktop-database
sudo update-mime-database /usr/share/mime

# Have tumbler pick up the new thumbnailers and drop cached failures
rm -rf "$HOME/.cache/thumbnails/fail"
pkill -x tumblerd || true
thunar -q 2>/dev/null || true
