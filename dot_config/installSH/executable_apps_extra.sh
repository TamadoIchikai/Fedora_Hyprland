#!/usr/bin/env bash
set -euo pipefail

#echo -e "${BLUE}-------> Installing brave browser${NC}"
#curl -fsS https://dl.brave.com/install.sh | sh

echo -e "${BLUE}-------> Install xournal dev via luya copr${NC}"
sudo dnf copr enable -y luya/xournalpp
sudo dnf install -y lua-lgi xournalpp keepassxc
echo -e "${GREEN}-------> DONE${NC}"

echo -e "${BLUE}-------> Install libre wolf as a secondary browser${NC}"
sudo dnf config-manager addrepo --from-repofile=https://repo.librewolf.net/librewolf.repo
sudo dnf install -y librewolf
echo -e "${GREEN}-------> DONE${NC}"

echo -e "${BLUE}-------> Installing flatpak apps (OBS)${NC}"
sudo dnf install -y flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak install -y flathub \
  com.obsproject.Studio \
  io.github.mpc_qt.mpc-qt \
  io.missioncenter.MissionCenter

echo -e "${BLUE}-------> Fix theme issues${NC}"
sudo dnf install -y kvantum qt5ct qt6ct

flatpak install -y flathub \
  org.gtk.Gtk3theme.adw-gtk3 \
  org.gtk.Gtk3theme.adw-gtk3-dark \
  org.kde.KStyle.Kvantum

mkdir -p ~/.config/Kvantum

cat > ~/.config/Kvantum/kvantum.kvconfig <<'EOF'
[General]
theme=KvGnomeDark
EOF

flatpak override --user \
  --env=GTK_THEME=adw-gtk3-dark \
  --env=GTK_ICON_THEME=Papirus-Dark \
  --env=ADW_DEBUG_COLOR_SCHEME=prefer-dark \
  --env=QT_STYLE_OVERRIDE=kvantum \
  --filesystem=xdg-config/Kvantum:ro \
  --filesystem=xdg-config/gtk-3.0:ro \
  --filesystem=xdg-config/gtk-4.0:ro \
  --filesystem=xdg-data/icons:ro \
  --filesystem=~/.icons:ro
echo -e "${GREEN}-------> DONE${NC}"
