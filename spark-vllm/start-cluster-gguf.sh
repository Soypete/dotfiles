#!/bin/bash
# Starts the vLLM cluster serving a local single-file GGUF (experimental).
# Companion to start-cluster.sh; run hf-download-gguf.sh first on both nodes'
# behalf (it downloads, merges shards, and rsyncs to the worker).
#
# STATUS: does NOT work for the default MiniMax-M3 GGUF. As of 2026-07 there is
# no minimax-m3 support anywhere in vLLM's GGUF stack (in-tree or plugin), so
# serve fails at weight load. Kept because the download/merge/distribute
# pipeline is sound and the flags carry over to supported GGUF archs. See
# RUNBOOK.md "GGUF (experimental)" for the full post-mortem and the llama.cpp
# alternative. Set GGUF_ALLOW_UNSUPPORTED=1 to run it anyway.
#
# Supported GGUF archs in the nvcr 26.02 container: qwen2 / qwen2moe / qwen3 /
# qwen3_moe and the llama family.
#
# GGUF in vLLM is experimental generally: single-file models only, and the
# loader supports a hardcoded architecture list.
#
# The nvcr 26.02 vLLM (0.17.x) has in-tree GGUF support — do NOT install
# vllm-gguf-plugin (0.0.x targets a newer vLLM API and fails to import).
#
# GGUF_PATH is the *container* path: launch-cluster.sh mounts host
# ~/.cache/huggingface at /root/.cache/huggingface.

set -euo pipefail

if [ "${GGUF_ALLOW_UNSUPPORTED:-0}" != "1" ]; then
  cat >&2 <<'EOF'
start-cluster-gguf.sh: refusing to start.

MiniMax-M3 GGUF is not servable by vLLM (no minimax-m3 in the in-tree loader or
vllm-gguf-plugin as of 2026-07). Starting anyway costs a cluster restart and
fails at weight load.

  - Full post-mortem:  RUNBOOK.md, "GGUF (experimental)"
  - Viable route for M3: llama.cpp (llama-server + rpc-server on the worker)
  - Serving a *supported* GGUF arch (qwen2/qwen3/llama family)? Re-run with:
      GGUF_ALLOW_UNSUPPORTED=1 GGUF_PATH=... ./start-cluster-gguf.sh
EOF
  exit 1
fi

SPARK_VLLM_DIR="${SPARK_VLLM_DIR:-$HOME/spark-vllm-docker}"
GGUF_PATH="${GGUF_PATH:-/root/.cache/huggingface/gguf/MiniMax-M3-GGUF/MiniMax-M3-UD-IQ3_XXS.gguf}"
BASE_MODEL="${BASE_MODEL:-MiniMaxAI/MiniMax-M3}"   # tokenizer + config source; GGUF tokenizer conversion is unstable
PARSER="${PARSER:-minimax_m2}"                     # M3-specific parser name unverified; flip here if one lands
MAX_MODEL_LEN="${MAX_MODEL_LEN:-128000}"           # IQ3_XXS leaves ~35GB/node KV headroom: full context fits
GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.90}"               # up from 0.7: ~79GB/node of weights vs ~58GB for M2.5-AWQ

cd "$SPARK_VLLM_DIR"

# Differences from start-cluster.sh: local .gguf path instead of a repo id,
# no --load-format fastsafetensors (format auto-detected),
# PIECEWISE cudagraphs (required for MoE on GB10, per RUNBOOK).
exec ./launch-cluster.sh exec bash -c "
  vllm serve '$GGUF_PATH' \
    --tokenizer '$BASE_MODEL' \
    --hf-config-path '$BASE_MODEL' \
    --trust-remote-code \
    --host 0.0.0.0 --port 8000 \
    --gpu-memory-utilization $GPU_MEM_UTIL \
    -tp 2 \
    --distributed-executor-backend ray \
    --max-model-len $MAX_MODEL_LEN \
    --compilation-config '{\"cudagraph_mode\": \"PIECEWISE\"}' \
    --enable-auto-tool-choice \
    --tool-call-parser $PARSER \
    --reasoning-parser $PARSER"
