#!/bin/bash
# Downloads a GGUF quant from Hugging Face, merges its shards into a single
# file (vLLM can only load single-file GGUFs), and rsyncs the result to the
# worker Spark. Run on spark-f5ea (head node). Safe to re-run: hf download
# resumes, merge is skipped when the merged file exists.
#
# Needs llama.cpp's llama-gguf-split utility (merge only — llama.cpp is not
# used for serving). Auto-detected from the existing build under ~/ai/llama.cpp;
# override with GGUF_SPLIT=/path/to/llama-gguf-split.
#
# Usage:
#   ./hf-download-gguf.sh
#   QUANT=UD-Q3_K_XL ./hf-download-gguf.sh          # smaller fallback quant
#   DELETE_SHARDS=1 ./hf-download-gguf.sh           # reclaim disk after merge

set -euo pipefail

REPO="${REPO:-unsloth/MiniMax-M3-GGUF}"
# UD-IQ3_XXS (159GB) chosen over UD-IQ4_NL (212GB): 4-bit weights leave ~9GB/node
# for KV cache on 2x128GB Sparks (~16-32K context); 3-bit leaves ~35GB/node,
# enough for the full 128K context OpenCode needs. See RUNBOOK fit table.
QUANT="${QUANT:-UD-IQ3_XXS}"
# Must be under a path launch-cluster.sh mounts into the container
# (~/.cache/huggingface is mounted by eugr/spark-vllm-docker).
DEST="${DEST:-$HOME/.cache/huggingface/gguf}"
WORKER="${WORKER:-169.254.91.57}"   # worker sshd is not reachable on the QSFP IP (192.168.100.11); this link still moves ~500MB/s
DELETE_SHARDS="${DELETE_SHARDS:-0}"

GGUF_SPLIT="${GGUF_SPLIT:-}"
if [ -z "$GGUF_SPLIT" ]; then
  for candidate in \
      "$HOME/ai/llama.cpp/build-cuda/bin/llama-gguf-split" \
      "$HOME/ai/llama.cpp/build/bin/llama-gguf-split" \
      "$(command -v llama-gguf-split || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      GGUF_SPLIT="$candidate"
      break
    fi
  done
fi

MODEL_DIR="$DEST/$(basename "$REPO")"

# --- tooling checks ---------------------------------------------------------
# ~/.local/bin explicitly: non-login shells (tmux, systemd) may not have it in PATH
HF_CLI=""
for candidate in "$(command -v hf || true)" "$HOME/.local/bin/hf" \
                 "$(command -v huggingface-cli || true)" "$HOME/.local/bin/huggingface-cli"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    HF_CLI="$candidate"
    break
  fi
done
if [ -z "$HF_CLI" ]; then
  echo "error: need the Hugging Face CLI: pip install -U 'huggingface_hub[cli]'" >&2
  exit 1
fi

if [ -z "$GGUF_SPLIT" ] || [ ! -x "$GGUF_SPLIT" ]; then
  echo "error: llama-gguf-split not found (looked under ~/ai/llama.cpp and PATH)" >&2
  echo "hint: set GGUF_SPLIT=/path/to/llama-gguf-split" >&2
  exit 1
fi
echo "[tools] using $GGUF_SPLIT"

# --- download ---------------------------------------------------------------
echo "[download] $REPO ($QUANT) -> $MODEL_DIR"
"$HF_CLI" download "$REPO" --include "*${QUANT}*" --local-dir "$MODEL_DIR"

mapfile -t SHARDS < <(find "$MODEL_DIR" -name "*${QUANT}*-00001-of-*.gguf" | sort)
if [ "${#SHARDS[@]}" -eq 0 ]; then
  # single-file quant: nothing to merge
  MERGED=$(find "$MODEL_DIR" -name "*${QUANT}*.gguf" | head -1)
  if [ -z "$MERGED" ]; then
    echo "error: no .gguf files matching $QUANT under $MODEL_DIR" >&2
    exit 1
  fi
  echo "[merge] single-file quant, no merge needed: $MERGED"
else
  FIRST_SHARD="${SHARDS[0]}"
  # MiniMax-M3-UD-IQ4_NL-00001-of-00005.gguf -> MiniMax-M3-UD-IQ4_NL.gguf
  MERGED="$MODEL_DIR/$(basename "$FIRST_SHARD" | sed -E 's/-[0-9]{5}-of-[0-9]{5}//')"

  if [ -f "$MERGED" ]; then
    echo "[merge] already merged: $MERGED"
  else
    # merge writes a full second copy: check disk before starting
    SHARD_DIR=$(dirname "$FIRST_SHARD")
    NEED_KB=$(du -sk "$SHARD_DIR" | cut -f1)
    AVAIL_KB=$(df -Pk "$MODEL_DIR" | awk 'NR==2 {print $4}')
    if [ "$AVAIL_KB" -lt "$NEED_KB" ]; then
      echo "error: merge needs ~$((NEED_KB / 1024 / 1024))GB free, only $((AVAIL_KB / 1024 / 1024))GB available" >&2
      echo "hint: free space or set DELETE_SHARDS=1 after a merge on another volume" >&2
      exit 1
    fi
    echo "[merge] ${#SHARDS[@]}+ shards -> $MERGED"
    "$GGUF_SPLIT" --merge "$FIRST_SHARD" "$MERGED"
  fi

  if [ "$DELETE_SHARDS" = "1" ]; then
    echo "[merge] deleting shards to reclaim disk"
    find "$MODEL_DIR" -name "*${QUANT}*-of-*.gguf" -delete
  fi
fi

# --- distribute to worker ---------------------------------------------------
# tp=2 loads weights on both nodes; the file must exist at the same path.
echo "[rsync] $MERGED -> $WORKER"
ssh -o BatchMode=yes "$WORKER" "mkdir -p '$(dirname "$MERGED")'"
rsync -av --progress "$MERGED" "$WORKER:$MERGED"

echo "[done] serve with: GGUF_PATH=$MERGED ./start-cluster-gguf.sh"
