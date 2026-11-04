#!/bin/bash
# Starts GLM-5.3-Flash (nvidia/GLM-5.3-Flash-FP4-Local) via eugr/spark-vllm-docker's recipe runner.
#
# This file is authored here in dotfiles but RUNS from ~/ on spark-f5ea — the
# Sparks have no dotfiles checkout, these scripts are scp'd over. vllm-cluster.service
# therefore points at /home/soypete/start-cluster-glm.sh, not a dotfiles path.
# After editing, re-deploy: see RUNBOOK.md "Deploying these scripts to the Sparks".
#
# Unlike start-cluster.sh (which calls launch-cluster.sh directly), this uses the
# recipe runner: recipes/glm-5.3-flash.yaml carries the B12X container (built with
# --exp-b12x), the SM121 env block, MTP spec decoding and --load-format b12x.
# Keeping the recipe as the source of truth means upstream fixes arrive with a git pull.
#
# First run on a node: ./run-recipe.sh glm-5.3-flash --setup -n $NODES builds the
# image and downloads ~166GiB of weights. Do that BEFORE switching START_SCRIPT, or
# the first systemd start will spend a long time downloading. The recipe's
# max-model-len is 500000; to lower it, edit a local copy of the recipe.

set -euo pipefail

SPARK_VLLM_DIR="${SPARK_VLLM_DIR:-$HOME/spark-vllm-docker}"
# Pinned, NOT "${RECIPE:-...}": systemd's manager environment can carry a stale RECIPE from an
# earlier `systemctl set-environment`, and an inherited value would silently launch another model.
RECIPE="glm-5.3-flash"
NODES="${NODES:-192.168.100.10,192.168.100.11}"

# uvx/hf live in ~/.local/bin, which non-login shells (systemd, tmux) don't have
# on PATH. The recipe runner shells out to hf-download.sh, which needs uvx.
export PATH="$HOME/.local/bin:$PATH"

cd "$SPARK_VLLM_DIR"

exec ./run-recipe.sh "$RECIPE" -n "$NODES"
