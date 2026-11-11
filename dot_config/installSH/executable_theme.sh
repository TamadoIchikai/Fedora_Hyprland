#!/usr/bin/env bash
# Unified dark theme for GTK3/GTK4/Qt5/Qt6 and Flatpak apps.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

GTK_THEME="adw-gtk3-dark"
ICON_THEME="Papirus-Dark"
CURSOR_THEME="Adwaita"

dnf_install \
  dconf gsettings-desktop-schemas \
  libadwaita adw-gtk3-theme \
  adwaita-icon-theme adwaita-icon-theme-legacy adwaita-cursor-theme \
  papirus-icon-theme breeze-icon-theme \
  kvantum qt5ct qt6ct

mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0 ~/.config/Kvantum ~/.config/qt6ct

# --- GTK ---
cat >~/.config/gtk-3.0/settings.ini <<CONF
[Settings]
gtk-theme-name=${GTK_THEME}
gtk-application-prefer-dark-theme=1
gtk-icon-theme-name=${ICON_THEME}
gtk-cursor-theme-name=${CURSOR_THEME}
CONF

cat >~/.config/gtk-4.0/settings.ini <<CONF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita
gtk-icon-theme-name=${ICON_THEME}
gtk-cursor-theme-name=${CURSOR_THEME}
CONF

gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME"
gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"
gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME"

# --- Qt (Kvantum + qt6ct) ---
cat >~/.config/Kvantum/kvantum.kvconfig <<'CONF'
[General]
theme=KvGnomeDark
CONF

cat >~/.config/qt6ct/qt6ct.conf <<'CONF'
[Appearance]
color_scheme_path=/usr/share/color-schemes/BreezeDark.colors
custom_palette=true
icon_theme=breeze-dark
standard_dialogs=default
style=kvantum-dark

[Fonts]
fixed="Noto Sans,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
general="Noto Sans,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"

[Interface]
activate_item_on_single_click=1
buttonbox_layout=0
cursor_flash_time=1000
dialog_buttons_have_icons=1
double_click_interval=400
gui_effects=@Invalid()
keyboard_scheme=2
menus_have_icons=true
show_shortcuts_in_context_menus=true
stylesheets=@Invalid()
toolbutton_style=4
underline_shortcut=1
wheel_scroll_lines=3

[SettingsWindow]
geometry=@ByteArray(\x1\xd9\xd0\xcb\0\x3\0\0\0\0\a\x80\0\0\0\0\0\0\xe\xf1\0\0\x4\b\0\0\a\x80\0\0\0\0\0\0\xe\xf1\0\0\x4\b\0\0\0\0\x2\0\0\0\a\x80\0\0\a\x80\0\0\0\0\0\0\xe\xf1\0\0\x4\b)

[Troubleshooting]
force_raster_widgets=1
ignored_applications=@Invalid()
CONF

# --- Flatpak apps: same theme for every app ---
flatpak_install \
  org.gtk.Gtk3theme.adw-gtk3 \
  org.gtk.Gtk3theme.adw-gtk3-dark \
  org.kde.KStyle.Kvantum//6.10 # several branches exist; must match the KDE 6.x runtime

flatpak override --user \
  --env=GTK_THEME="$GTK_THEME" \
  --env=GTK_ICON_THEME="$ICON_THEME" \
  --env=ADW_DEBUG_COLOR_SCHEME=prefer-dark \
  --env=QT_STYLE_OVERRIDE=kvantum \
  --filesystem=xdg-config/Kvantum:ro \
  --filesystem=xdg-config/gtk-3.0:ro \
  --filesystem=xdg-config/gtk-4.0:ro \
  --filesystem=xdg-data/icons:ro \
  --filesystem=~/.icons:ro
