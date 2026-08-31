#!/bin/bash
# Starts DeepSeek-V4-Flash-0731 via eugr/spark-vllm-docker's recipe runner.
#
# This file is authored here in dotfiles but RUNS from ~/ on spark-f5ea — the
# Sparks have no dotfiles checkout, these scripts are scp'd over. vllm-cluster.service
# therefore points at /home/soypete/start-cluster-deepseek.sh, not a dotfiles path.
# After editing, re-deploy: see RUNBOOK.md "Deploying these scripts to the Sparks".
#
# Unlike start-cluster.sh (which calls launch-cluster.sh directly), this uses the
# recipe runner: recipes/deepseek-v4-flash-0731.yaml carries the B12X container,
# the SM121 env block, and the instanttensor draft-loader mod. Keeping the recipe
# as the source of truth means upstream fixes arrive with a git pull.

set -euo pipefail

SPARK_VLLM_DIR="${SPARK_VLLM_DIR:-$HOME/spark-vllm-docker}"
RECIPE="${RECIPE:-deepseek-v4-flash-0731}"
NODES="${NODES:-192.168.100.10,192.168.100.11}"

# uvx/hf live in ~/.local/bin, which non-login shells (systemd, tmux) don't have
# on PATH. The recipe runner shells out to hf-download.sh, which needs uvx.
export PATH="$HOME/.local/bin:$PATH"

cd "$SPARK_VLLM_DIR"

exec ./run-recipe.sh "$RECIPE" -n "$NODES"
