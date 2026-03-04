#!/bin/bash
# List available models in the exo cluster

API_URL="http://localhost:52415"

if ! curl -s "$API_URL/models" > /dev/null 2>&1; then
  echo "❌ Cannot connect to exo cluster at $API_URL"
  echo "Make sure the cluster is running:"
  echo "  ~/dotfiles/exo/scripts/start-cluster.sh"
  exit 1
fi

echo "=== Available Models ==="
curl -s "$API_URL/models" | jq -r '.[] | "- \(.id) (\(.size))"'
echo ""
echo "To use a model with Claude Code, set:"
echo "  export ANTHROPIC_MODEL=\"<model-id>\""
