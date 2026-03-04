#!/bin/bash
# Install exo on Mac mini Spark machines
# Run this script on each Spark machine (100.87.122.109)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Installing Exo on Spark Mac Mini ===${NC}"
echo ""

# Check macOS version
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d '.' -f 1)

echo -e "macOS Version: ${YELLOW}${MACOS_VERSION}${NC}"

if [ "$MACOS_MAJOR" -lt 15 ]; then
  echo -e "${RED}Warning: Exo app requires macOS Tahoe 26.2+ (macOS 15+)${NC}"
  echo "Your version: $MACOS_VERSION"
  echo ""
  echo "You may need to update macOS or use the source installation method."
  read -p "Continue anyway? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Download the latest DMG
DMG_URL="https://assets.exolabs.net/EXO-latest.dmg"
TEMP_DMG="/tmp/exo-latest.dmg"

echo ""
echo -e "${YELLOW}Downloading Exo DMG...${NC}"
curl -L -o "$TEMP_DMG" "$DMG_URL"

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to download Exo DMG${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Download complete${NC}"
echo ""

# Mount the DMG
echo -e "${YELLOW}Mounting DMG...${NC}"
MOUNT_POINT=$(hdiutil attach "$TEMP_DMG" | grep Volumes | awk '{print $3}')

if [ -z "$MOUNT_POINT" ]; then
  echo -e "${RED}Failed to mount DMG${NC}"
  exit 1
fi

echo -e "${GREEN}✓ DMG mounted at: ${MOUNT_POINT}${NC}"
echo ""

# Copy app to Applications
echo -e "${YELLOW}Installing Exo.app to /Applications...${NC}"
cp -R "${MOUNT_POINT}/EXO.app" /Applications/

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to copy app to /Applications${NC}"
  hdiutil detach "$MOUNT_POINT"
  exit 1
fi

echo -e "${GREEN}✓ Exo.app installed${NC}"

# Unmount DMG
hdiutil detach "$MOUNT_POINT" > /dev/null 2>&1

# Clean up
rm "$TEMP_DMG"

echo ""
echo -e "${GREEN}=== Installation Complete! ===${NC}"
echo ""
echo "Next steps:"
echo "1. Open Exo.app from Applications"
echo "2. Or run from command line: open -a EXO"
echo ""
echo -e "${YELLOW}The exo cluster will use namespace: soypete-spark-cluster${NC}"
echo "This ensures both Spark machines connect to the same cluster."
echo ""
echo "Dashboard will be available at: http://localhost:52415"
