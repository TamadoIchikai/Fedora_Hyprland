BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' 

set -e
echo -e "${BLUE}-------> Install some bloatwares lmao${NC}"
sudo dnf install foot fuzzel fzf zsh firefox

echo "${BLUE}------->install flatpak related apps like obsidian, mission center${NC}"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub io.missioncenter.MissionCenter
flatpak override --user --socket=system-bus org.missioncenter.MissionCenter
flatpak install flathub it.mijorus.gearlever

echo "${BLUE}-------> install minimal cargo for some app like zoxide${NC}"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile=minimal
cargo install zoxide --locked

echo "${BLUE}------->Building rofi for wayland support${NC}"
sudo dnf install cairo-devel pango-devel glib2-devel libxkbcommon-devel wayland-devel wayland-protocols-devel pkg-config meson cmake gdk-pixbuf2-devel
cd Downloads/Systems/
git clone https://github.com/davatorium/rofi.git
cd rofi
meson setup build -Dwayland=enabled -Dxcb=disabled
ninja -C build
echo -e "${GREEN}-------> DONE${NC}"
