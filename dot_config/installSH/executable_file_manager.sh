BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

set -e
echo -e "${BLUE}-------> Installing Thunar file manager${NC}"
sudo dnf install -y thunar thunar-archive-plugin thunar-volman gsettings-desktop-schemas
echo -e "${GREEN}-------> DONE${NC}"

