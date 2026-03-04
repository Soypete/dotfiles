#!/bin/bash
# Deploy exo installation script to both Spark machines via Tailscale

# Spark machine IPs (both coupled at same IP)
SPARK_IP="100.87.122.109"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install-on-spark.sh"

echo -e "${GREEN}=== Deploying Exo Installation to Spark Machines ===${NC}"
echo ""
echo "Target IP: $SPARK_IP"
echo ""

# Check if install script exists
if [ ! -f "$INSTALL_SCRIPT" ]; then
  echo "Error: install-on-spark.sh not found"
  exit 1
fi

echo -e "${YELLOW}Copying installation script to Spark machines...${NC}"

# Copy to Spark
scp "$INSTALL_SCRIPT" "soypete@${SPARK_IP}:/tmp/install-exo.sh"

if [ $? -ne 0 ]; then
  echo "Failed to copy script to Spark machines"
  exit 1
fi

echo -e "${GREEN}✓ Script copied${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. SSH to each Spark machine:"
echo "   ssh soypete@${SPARK_IP}"
echo ""
echo "2. Run the installation script on each:"
echo "   bash /tmp/install-exo.sh"
echo ""
echo "3. Start Exo on both Sparks (they will auto-discover each other)"
echo "   open -a EXO"
echo ""
echo -e "${YELLOW}Note:${NC} Both Spark machines share namespace 'soypete-spark-cluster'"
