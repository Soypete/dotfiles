#!/bin/bash
# Pre-start cleanup: wipe vllm_node containers on both Sparks so Ray comes up
# with a clean placement-group state. Invoked by vllm-cluster.service.
# Failures are non-fatal — a missing container is the expected case.

set -u

CONTAINER="${CONTAINER:-vllm_node}"
WORKER_HOST="${WORKER_HOST:-169.254.91.57}"

echo "[cleanup] stopping local container '$CONTAINER' if present..."
docker stop "$CONTAINER" 2>/dev/null || true
docker rm   "$CONTAINER" 2>/dev/null || true

echo "[cleanup] stopping remote container on $WORKER_HOST..."
ssh -o BatchMode=yes -o ConnectTimeout=5 "$WORKER_HOST" \
  "docker stop $CONTAINER 2>/dev/null; docker rm $CONTAINER 2>/dev/null" \
  || echo "[cleanup] warning: could not reach $WORKER_HOST (continuing anyway)"

echo "[cleanup] done"
exit 0
