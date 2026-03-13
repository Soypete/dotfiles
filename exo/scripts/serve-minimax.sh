#!/bin/bash
SAFETENSORS_FAST_GPU=1 vllm serve QuantTrio/MiniMax-M2.5-AWQ --trust-remote-code --tensor-parallel-size 2 --distributed-executor-backend ray --max-model-len 32768 --enable-auto-tool-choice --tool-call-parser minimax_m2 --reasoning-parser minimax_m2_append_think --host 0.0.0.0 --port 8000
