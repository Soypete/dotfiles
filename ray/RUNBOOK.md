# Ray Cluster Runbook

## Hardware
- **spark-f5ea** (Node 1, head): 192.168.1.X LAN, 192.168.100.10 QSFP
- **spark-771e** (Node 2, worker): 192.168.1.84 LAN, 192.168.100.11 QSFP

## Start Sequence

Uses `eugr/spark-vllm-docker` which handles container setup, Ray cluster, and model serving.

### Start the cluster

On spark-f5ea (head node):
```bash
sudo systemctl start vllm-cluster
```

Startup takes ~5-6 minutes. Wait for: `Application startup complete.`

### Verify

```bash
curl http://100.87.122.109:8000/v1/models
```

---

## Restart Sequence

```bash
sudo systemctl restart vllm-cluster
```

---

## Persistent IP Configuration (do once per node)

Without this, QSFP IPs are lost on reboot.

On spark-f5ea:
```bash
sudo tee /etc/netplan/99-qsfp-static.yaml << 'EOF'
network:
  version: 2
  ethernets:
    enp1s0f0np0:
      addresses:
        - 192.168.100.10/24
EOF
sudo netplan apply
```

On spark-771e:
```bash
sudo tee /etc/netplan/99-qsfp-static.yaml << 'EOF'
network:
  version: 2
  ethernets:
    enp1s0f0np0:
      addresses:
        - 192.168.100.11/24
EOF
sudo netplan apply
```

---

## Troubleshooting

### "Failed to connect to GCS at 192.168.100.10:6379"
Head node isn't running yet, or QSFP interface has no IP. Check:
```bash
ip addr show enp1s0f0np0   # should show 192.168.100.x
docker ps                  # head container should be running on spark-f5ea
```

### Ray shows 1 GPU instead of 2
Node 2's container started without GPU access, or it's still connected from a previous crashed session. Restart both containers.

### "Current node has no GPU available"
GPU is still reserved by a previous placement group. `launch-cluster.sh exec` won't fix this because it skips container restart when containers are already running. You must manually stop and remove containers on both nodes first:
```bash
docker stop vllm_node && docker rm vllm_node
ssh 169.254.91.57 'docker stop vllm_node && docker rm vllm_node'
```
Then re-run `./launch-cluster.sh exec vllm serve ...` to get fresh containers with clean Ray state.

### CUDA launch failure on Node 2 during weight load
Model wasn't pre-cached on Node 2. Download first:
```bash
export VLLM_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^node-[0-9]+')
docker exec -it $VLLM_CONTAINER bash -c 'huggingface-cli download QuantTrio/MiniMax-M2.5-AWQ'
```
Then always use `--compilation-config '{"cudagraph_mode": "PIECEWISE"}'`.

### Server crashes during inference (Node 2 ActorDiedError)
OOM kill on Node 2 during a large context request. Reduce `--max-model-len` or avoid sending requests >16k tokens.

### Context length errors from OpenCode
OpenCode compaction sends large context windows. Either reduce `--max-model-len` to match what the hardware supports, or start a fresh OpenCode session to reduce context size.

### Line wrapping breaks long commands in terminal
iTerm2 wraps pasted commands, breaking them at newlines. Use one-liners or write to a script file:
```bash
docker exec $VLLM_CONTAINER bash -c 'cat > /tmp/serve.sh << '"'"'EOF'"'"'
<serve command here>
EOF
bash /tmp/serve.sh'
```

---

## Downloading Models

```bash
./hf-download.sh QuantTrio/MiniMax-M2.5-AWQ -c --copy-parallel
```

---

## Serving Models

```bash
cd ~/spark-vllm-docker

./launch-cluster.sh exec vllm serve \
  QuantTrio/MiniMax-M2.5-AWQ \
  --trust-remote-code \
  --port 8000 --host 0.0.0.0 \
  --gpu-memory-utilization 0.7 \
  -tp 2 \
  --distributed-executor-backend ray \
  --max-model-len 128000 \
  --compilation-config '{"cudagraph_mode": "PIECEWISE"}' \
  --enable-auto-tool-choice --tool-call-parser minimax_m2 \
  --reasoning-parser minimax_m2_append_think
```

---

## Model Notes

| Model | Status | Notes |
|---|---|---|
| `QuantTrio/MiniMax-M2.5-AWQ` | ✅ Working | eugr/spark-vllm-docker, minimax_m2 parser, PIECEWISE required |
| `zai-org/GLM-4.5-Air` | ❌ Not working | 99.6GB, never got working on dual Spark |

## Model Selection Resources

- **LiveBench** (open-weight, high unseen bias filter): https://livebench.ai/#/?openweight=true&highunseenbias=true
  - Use this to compare open-weight models on benchmarks with low data contamination risk
  - Filter by context length and task type to find candidates for this cluster
