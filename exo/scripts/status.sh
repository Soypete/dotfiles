#!/bin/bash
# Check exo cluster status

API_URL="http://localhost:52415"

echo "=== Exo Cluster Status ==="
echo ""

# Check if exo is running
if ! curl -s "$API_URL/state" > /dev/null 2>&1; then
  echo "❌ Exo cluster is not running"
  echo ""
  echo "Start the cluster with:"
  echo "  ~/dotfiles/exo/scripts/start-cluster.sh"
  exit 1
fi

echo "✅ Exo cluster is running"
echo ""

# Get cluster state
echo "=== Cluster State ==="
curl -s "$API_URL/state" | jq '.'
echo ""

# List available models
echo "=== Available Models ==="
curl -s "$API_URL/models" | jq '.'
echo ""

echo "Dashboard: http://localhost:52415"
