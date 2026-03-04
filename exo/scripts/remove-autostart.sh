#!/bin/bash
# Remove exo auto-start configuration

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PLIST_PATH="$HOME/Library/LaunchAgents/com.soypete.exo.plist"

echo -e "${YELLOW}Removing exo auto-start...${NC}"

if [ ! -f "$PLIST_PATH" ]; then
    echo "Auto-start is not configured (plist not found)"
    exit 0
fi

# Unload the service
launchctl unload "$PLIST_PATH"

# Remove the plist file
rm "$PLIST_PATH"

echo -e "${GREEN}✓ Auto-start removed${NC}"
echo ""
echo "Exo will no longer start automatically."
echo "You can manually start it with:"
echo "  cd ~/code/exo && uv run exo"
