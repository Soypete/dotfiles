#!/bin/bash
# Start exo cluster with custom namespace
# This script starts the exo cluster on your local machine

# Set custom namespace to isolate your cluster
export EXO_LIBP2P_NAMESPACE="soypete-spark-cluster"

# Change to exo installation directory
EXO_DIR="${HOME}/code/exo"

if [ ! -d "$EXO_DIR" ]; then
  echo "Error: exo not found at $EXO_DIR"
  echo "Please clone and build exo first:"
  echo "  git clone https://github.com/exo-explore/exo ${EXO_DIR}"
  echo "  cd ${EXO_DIR}/dashboard && npm install && npm run build && cd .."
  exit 1
fi

cd "$EXO_DIR"

# Start exo with logging
echo "Starting exo cluster with namespace: $EXO_LIBP2P_NAMESPACE"
echo "Dashboard will be available at: http://localhost:52415"
echo "Logs will be saved to: ~/dotfiles/exo/logs/exo.log"

# Run exo and log output
uv run exo 2>&1 | tee ~/dotfiles/exo/logs/exo.log
