#!/bin/bash
# Setup exo to run automatically at startup using launchd
# Run this script on each Spark machine

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_SOURCE="${SCRIPT_DIR}/../config/com.soypete.exo.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/com.soypete.exo.plist"

# Update username in plist if needed
CURRENT_USER=$(whoami)

echo -e "${GREEN}=== Setting up Exo Auto-start ===${NC}"
echo ""

# Check if exo is installed
if [ ! -d "$HOME/code/exo" ]; then
    echo -e "${RED}Error: exo not found at $HOME/code/exo${NC}"
    echo "Please install exo first:"
    echo "  git clone https://github.com/exo-explore/exo ~/code/exo"
    echo "  cd ~/code/exo/dashboard && npm install && npm run build && cd .."
    exit 1
fi

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo -e "${RED}Error: uv not found${NC}"
    echo "Please install uv first:"
    echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

# Create LaunchAgents directory if it doesn't exist
mkdir -p "$HOME/Library/LaunchAgents"

# Create logs directory (use ~/exo on Sparks, ~/dotfiles/exo on Mac Studio)
if [ -d "$HOME/dotfiles/exo" ]; then
    LOGS_DIR="$HOME/dotfiles/exo/logs"
else
    LOGS_DIR="$HOME/exo/logs"
fi
mkdir -p "$LOGS_DIR"

# Update log paths in plist
sed -i '' "s|/Users/soypete/dotfiles/exo/logs|${LOGS_DIR}|g" "$PLIST_DEST"

# Copy and update plist file with current username
echo -e "${YELLOW}Installing launchd configuration...${NC}"
sed "s/soypete/${CURRENT_USER}/g" "$PLIST_SOURCE" > "$PLIST_DEST"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to copy plist file${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Configuration installed${NC}"

# Unload if already loaded (ignore errors)
launchctl unload "$PLIST_DEST" 2>/dev/null

# Load the new configuration
echo -e "${YELLOW}Loading exo service...${NC}"
launchctl load "$PLIST_DEST"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to load service${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Service loaded${NC}"
echo ""
echo -e "${GREEN}=== Auto-start Setup Complete! ===${NC}"
echo ""
echo "Exo will now:"
echo "  - Start automatically when you log in"
echo "  - Restart automatically if it crashes"
echo "  - Use namespace: soypete-spark-cluster"
echo ""
echo "Logs are available at:"
echo "  ~/dotfiles/exo/logs/exo-startup.log"
echo "  ~/dotfiles/exo/logs/exo-startup-error.log"
echo ""
echo "To manage the service:"
echo "  Stop:   launchctl unload ~/Library/LaunchAgents/com.soypete.exo.plist"
echo "  Start:  launchctl load ~/Library/LaunchAgents/com.soypete.exo.plist"
echo "  Status: launchctl list | grep com.soypete.exo"
echo ""
echo "Dashboard: http://localhost:52415"
