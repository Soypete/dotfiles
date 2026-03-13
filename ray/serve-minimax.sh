#!/bin/bash
# Serve QuantTrio/MiniMax-M2.5-AWQ across both Ray nodes
# Run inside the vLLM container on Node 1 after cluster is up
#
# NOTE: MiniMax-M2.5-AWQ uses TransformersForCausalLM architecture which is not
# natively supported by vLLM 26.02-py3 (0.11.0). Waiting on upstream vLLM support.
# The 'minimax' tool call parser IS available in 26.02-py3.
# minimax_m2_append_think reasoning parser is NOT available - use 'minimax' only.

SAFETENSORS_FAST_GPU=1 vllm serve QuantTrio/MiniMax-M2.5-AWQ --trust-remote-code --tensor-parallel-size 2 --distributed-executor-backend ray --max-model-len 32768 --enable-auto-tool-choice --tool-call-parser minimax --compilation-config '{"cudagraph_mode": "PIECEWISE"}' --host 0.0.0.0 --port 8000
