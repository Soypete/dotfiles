#!/bin/bash
# Deploy and enable exo as a systemd service on Spark f5ea (Ubuntu Linux)
# Run this from the Mac Studio

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SPARK_IP="100.87.122.109"
SPARK_USER="soypete"

echo -e "${GREEN}=== Setting up Exo systemd service on Spark ===${NC}"
echo "Target: ${SPARK_USER}@${SPARK_IP}"
echo ""

# Write the systemd unit file on the Spark and enable it
ssh "${SPARK_USER}@${SPARK_IP}" bash << 'ENDSSH'
set -e

SERVICE_FILE="/etc/systemd/system/exo.service"

echo "Creating systemd service..."
sudo tee "$SERVICE_FILE" > /dev/null << 'EOF'
[Unit]
Description=Exo Cluster Node
After=network.target tailscaled.service

[Service]
User=soypete
WorkingDirectory=/home/soypete/code/exo
Environment=HOME=/home/soypete
Environment=EXO_LIBP2P_NAMESPACE=soypete_tech
Environment=PATH=/home/soypete/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/bin/bash -lc 'cd /home/soypete/code/exo && uv run exo'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable exo
sudo systemctl restart exo

echo ""
echo "Service status:"
sudo systemctl status exo --no-pager -l
ENDSSH

if [ $? -eq 0 ]; then
  echo ""
  echo -e "${GREEN}✓ Exo systemd service enabled and started on Spark${NC}"
  echo ""
  echo "Manage with:"
  echo "  ssh ${SPARK_USER}@${SPARK_IP} 'sudo systemctl status exo'"
  echo "  ssh ${SPARK_USER}@${SPARK_IP} 'sudo systemctl restart exo'"
  echo "  ssh ${SPARK_USER}@${SPARK_IP} 'sudo journalctl -u exo -f'"
else
  echo -e "${RED}Failed to set up systemd service${NC}"
  exit 1
fi
