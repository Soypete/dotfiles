#!/bin/bash
# Starts DeepSeek-V4-Flash (NON-B12X) via eugr/spark-vllm-docker's recipe runner.
#
# This file is authored here in dotfiles but RUNS from ~/ on spark-f5ea — the
# Sparks have no dotfiles checkout, these scripts are scp'd over. vllm-cluster.service
# therefore points at /home/soypete/start-cluster-deepseek-ray.sh, not a dotfiles path.
# After editing, re-deploy: see RUNBOOK.md "Deploying these scripts to the Sparks".
#
# Why this exists alongside start-cluster-deepseek.sh:
#   recipes/deepseek-v4-flash-0731.yaml uses NVIDIA's *experimental* B12X stack —
#   the vllm-node-b12x container, B12X_MLA_SPARSE attention, b12x MoE/linear
#   backends, the instanttensor draft-loader mod, dspark speculative decoding and
#   16 VLLM_USE_B12X_*/B12X_* env vars. It also drops Ray: no
#   --distributed-executor-backend, so vLLM uses MultiprocExecutor + NCCL.
#
#   recipes/deepseek-v4-flash.yaml (this one) is the conservative path:
#     - stock `vllm-node` container (not b12x)
#     - --distributed-executor-backend ray
#     - no --moe-backend / --linear-backend flags
#     - 3 env vars instead of 16, none of them B12X
#     - mtp speculative decoding instead of dspark
#   It keeps --kv-cache-dtype fp8 and prefix caching.
#
#   NOTE: it serves deepseek-ai/DeepSeek-V4-Flash — a DIFFERENT checkpoint from
#   the -0731 one, so it needs its own ~167GB download on both nodes.

set -euo pipefail

SPARK_VLLM_DIR="${SPARK_VLLM_DIR:-$HOME/spark-vllm-docker}"
RECIPE="${RECIPE:-deepseek-v4-flash}"
NODES="${NODES:-192.168.100.10,192.168.100.11}"

# The recipe defaults to max_model_len 500000, which overruns the per-device
# buffer budget on 128GB GB10s:
#   RuntimeError: buffer_size (1059061760 B) exceeds device memory budget (754274304 B)
# 128K matches what MiniMax serves here and leaves headroom. Raise carefully.
MAX_MODEL_LEN="${MAX_MODEL_LEN:-131072}"

# uvx/hf live in ~/.local/bin, which non-login shells (systemd, tmux) don't have
# on PATH. The recipe runner shells out to hf-download.sh, which needs uvx.
export PATH="$HOME/.local/bin:$PATH"

cd "$SPARK_VLLM_DIR"

exec ./run-recipe.sh "$RECIPE" -n "$NODES" --max-model-len "$MAX_MODEL_LEN"
