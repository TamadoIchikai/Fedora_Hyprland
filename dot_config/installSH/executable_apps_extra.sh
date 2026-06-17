#!/usr/bin/env bash
set -euo pipefail

sudo dnf install -y lua-lgi xournalpp keepassxc flatpak

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak install -y flathub \
  com.obsproject.Studio \
  io.github.mpc_qt.mpc-qt \
  io.missioncenter.MissionCenter \
  eu.betterbird.Betterbird

sudo dnf install -y \
  libadwaita \
  adwaita-icon-theme \
  adwaita-cursor-theme \
  adwaita-icon-theme-legacy \
  adw-gtk3-theme \
  kvantum qt5ct qt6ct

mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0 ~/.config/Kvantum

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
 
