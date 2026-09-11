#!/usr/bin/env bash
set -euo pipefail

sudo dnf install -y lua-lgi xournalpp keepassxc flatpak

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak install -y flathub \
  com.obsproject.Studio \
  io.missioncenter.MissionCenter \
  eu.betterbird.Betterbird \
  com.github.tchx84.Flatseal \
  md.obsidian.Obsidian \
  net.ankiweb.Anki

sudo dnf install -y \
  libadwaita \
  adwaita-icon-theme \
  adwaita-cursor-theme \
  adwaita-icon-theme-legacy \
  adw-gtk3-theme breeze-icon-theme \
  kvantum qt5ct qt6ct

mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0 ~/.config/Kvantum ~/.config/qt6ct

cat > ~/.config/gtk-3.0/settings.ini <<'EOF'
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-application-prefer-dark-theme=1
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
EOF

cat > ~/.config/gtk-4.0/settings.ini <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
EOF

cat > ~/.config/Kvantum/kvantum.kvconfig <<'EOF'
[General]
theme=KvGnomeDark
EOF

cat > ~/.config/qt6ct/qt6ct.conf <<'EOF'
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
EOF

cat >
flatpak install -y flathub \
  org.gtk.Gtk3theme.adw-gtk3 \
  org.gtk.Gtk3theme.adw-gtk3-dark \
  org.kde.KStyle.Kvantum

flatpak override --user \
  --env=GTK_THEME=adw-gtk3-dark \
  --env=GTK_ICON_THEME=Papirus-Dark \
  --env=ADW_DEBUG_COLOR_SCHEME=prefer-dark \
  --env=QT_STYLE_OVERRIDE=kvantum \
  --filesystem=xdg-config/Kvantum:ro \
  --filesystem=xdg-config/gtk-3.0:ro \
  --filesystem=xdg-config/gtk-4.0:ro \
  --filesystem=xdg-data/icons:ro \
  --filesystem=~/.icons:ro \

flatpak override --user \
  --filesystem=/mnt/sda2/BetterBird/ \
  --filesystem=~/Downloads/tmp/ \
  --env=GTK_USE_PORTAL=1 \
  eu.betterbird.Betterbird

flatpak override --user \
    --unshare=network \
    --filesystem="${RESTIC_SOURCE_BASE}/Obsidian" \
    md.obsidian.Obsidian
