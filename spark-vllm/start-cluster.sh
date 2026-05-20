#!/bin/bash
# Starts the vLLM cluster via eugr/spark-vllm-docker's launch-cluster.sh.
# Invoked by systemd unit at dotfiles/spark-vllm/systemd/vllm-cluster.service.

set -euo pipefail

SPARK_VLLM_DIR="${SPARK_VLLM_DIR:-$HOME/spark-vllm-docker}"
MODEL="${MODEL:-QuantTrio/MiniMax-M2.5-AWQ}"

cd "$SPARK_VLLM_DIR"

exec ./launch-cluster.sh exec vllm serve "$MODEL" \
  --trust-remote-code \
  --host 0.0.0.0 --port 8000 \
  --gpu-memory-utilization 0.7 \
  -tp 2 \
  --distributed-executor-backend ray \
  --max-model-len 128000 \
  --load-format fastsafetensors \
  --enable-auto-tool-choice \
  --tool-call-parser minimax_m2 \
  --reasoning-parser minimax_m2
