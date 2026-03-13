#!/bin/bash
# Serve GLM-4.7-Flash across both Ray nodes
# Run this inside the vLLM container on Node 1 after cluster is up:
#   export VLLM_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^node-[0-9]+')
#   docker exec -it $VLLM_CONTAINER bash /tmp/serve-glm47.sh

SAFETENSORS_FAST_GPU=1 vllm serve zai-org/GLM-4.7-Flash --trust-remote-code --tensor-parallel-size 2 --distributed-executor-backend ray --max-model-len 32768 --enable-auto-tool-choice --tool-call-parser glm45 --reasoning-parser glm45 --speculative-config.method mtp --speculative-config.num_speculative_tokens 1 --served-model-name glm-4.7-flash --compilation-config '{"cudagraph_mode": "PIECEWISE"}' --host 0.0.0.0 --port 8000
# NOTE: glm47 parser does not exist in 26.02-py3, use glm45 instead
# NOTE: GLM-4.7-Flash requires transformers>=5.x but vLLM 26.02-py3 pins transformers==4.57.1
# This model will work once NVIDIA ships a newer vLLM container with transformers 5.x
