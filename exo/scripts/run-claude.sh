#!/bin/bash
# Helper script to run Claude Code with exo cluster and specific model

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if exo is running
if ! curl -s http://localhost:52415/state > /dev/null 2>&1; then
  echo -e "${RED}❌ Exo cluster is not running${NC}"
  echo ""
  echo "Start the cluster first:"
  echo "  exo-start"
  exit 1
fi

# If no model specified, show usage and available models
if [ -z "$1" ]; then
  echo "Usage: $0 <model-id>"
  echo ""
  echo -e "${YELLOW}Available models:${NC}"
  "$SCRIPT_DIR/models.sh"
  echo ""
  echo -e "${YELLOW}Example:${NC}"
  echo "  exo-claude meta-llama/Llama-3.3-70B-Instruct"
  echo ""
  echo -e "${YELLOW}Common smaller models for your setup:${NC}"
  echo "  - meta-llama/Llama-3.1-8B-Instruct"
  echo "  - Qwen/Qwen2.5-7B-Instruct"
  echo "  - deepseek-ai/DeepSeek-R1-Distill-Llama-8B"
  exit 1
fi

MODEL="$1"

echo -e "${GREEN}Starting Claude Code with exo cluster${NC}"
echo -e "Model: ${YELLOW}${MODEL}${NC}"
echo -e "API: ${YELLOW}http://localhost:52415/v1${NC}"
echo ""

# Run Claude Code with exo backend
ANTHROPIC_AUTH_TOKEN="" \
ANTHROPIC_BASE_URL="http://localhost:52415/v1" \
claude --model "$MODEL"
