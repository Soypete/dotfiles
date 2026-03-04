#!/bin/bash
# Deploy exo configuration files to Spark machines

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXO_DIR="$(dirname "$SCRIPT_DIR")"

SPARK1_IP="100.87.122.109"
SPARK2_IP="100.112.230.20"

echo -e "${GREEN}=== Deploying Exo Configuration to Sparks ===${NC}"
echo ""

# Function to deploy to a Spark
deploy_to_spark() {
    local SPARK_IP=$1
    local SPARK_NAME=$2

    echo -e "${YELLOW}Deploying to ${SPARK_NAME} (${SPARK_IP})...${NC}"

    # Create directories on Spark
    ssh soypete@${SPARK_IP} "mkdir -p ~/exo/{config,scripts,logs}"

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create directories on ${SPARK_NAME}${NC}"
        return 1
    fi

    # Copy config files
    scp "${EXO_DIR}/config/com.soypete.exo.plist" soypete@${SPARK_IP}:~/exo/config/
    scp "${EXO_DIR}/config/MODELS.md" soypete@${SPARK_IP}:~/exo/config/
    scp "${EXO_DIR}/config/README.md" soypete@${SPARK_IP}:~/exo/config/
    scp "${EXO_DIR}/config/AUTOSTART.md" soypete@${SPARK_IP}:~/exo/config/

    # Copy scripts
    scp "${EXO_DIR}/scripts/setup-autostart.sh" soypete@${SPARK_IP}:~/exo/scripts/
    scp "${EXO_DIR}/scripts/remove-autostart.sh" soypete@${SPARK_IP}:~/exo/scripts/
    scp "${EXO_DIR}/scripts/status.sh" soypete@${SPARK_IP}:~/exo/scripts/
    scp "${EXO_DIR}/scripts/models.sh" soypete@${SPARK_IP}:~/exo/scripts/

    # Make scripts executable
    ssh soypete@${SPARK_IP} "chmod +x ~/exo/scripts/*.sh"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Deployed to ${SPARK_NAME}${NC}"
        echo ""
    else
        echo -e "${RED}✗ Failed to deploy to ${SPARK_NAME}${NC}"
        echo ""
        return 1
    fi
}

# Deploy to Spark 1
deploy_to_spark "$SPARK1_IP" "Spark 1"

# Ask if we should deploy to Spark 2
echo ""
read -p "Deploy to Spark 2 (requires SSH from Spark 1)? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deploying to Spark 2 via Spark 1...${NC}"

    # We need to go through Spark 1 to reach Spark 2
    ssh soypete@${SPARK1_IP} "bash -s" <<'ENDSSH'
        SPARK2_IP="100.112.230.20"

        # Create directories on Spark 2
        ssh soypete@${SPARK2_IP} "mkdir -p ~/exo/{config,scripts,logs}"

        # Copy files from Spark 1 to Spark 2
        scp -r ~/exo/config/* soypete@${SPARK2_IP}:~/exo/config/
        scp -r ~/exo/scripts/* soypete@${SPARK2_IP}:~/exo/scripts/

        # Make scripts executable
        ssh soypete@${SPARK2_IP} "chmod +x ~/exo/scripts/*.sh"
ENDSSH

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Deployed to Spark 2${NC}"
    else
        echo -e "${RED}✗ Failed to deploy to Spark 2${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=== Deployment Complete! ===${NC}"
echo ""
echo "Next steps on each Spark:"
echo ""
echo "1. SSH to the Spark:"
echo "   ssh soypete@${SPARK1_IP}"
echo ""
echo "2. Clone and build exo (if not already done):"
echo "   git clone https://github.com/exo-explore/exo ~/code/exo"
echo "   cd ~/code/exo/dashboard && npm install && npm run build && cd .."
echo ""
echo "3. Set namespace in .zshrc:"
echo "   echo 'export EXO_LIBP2P_NAMESPACE=\"soypete-spark-cluster\"' >> ~/.zshrc"
echo "   source ~/.zshrc"
echo ""
echo "4. Setup auto-start:"
echo "   ~/exo/scripts/setup-autostart.sh"
echo ""
echo "Files deployed to: ~/exo/ on each Spark"
