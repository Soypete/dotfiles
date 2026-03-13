# Ray Cluster Runbook

## Hardware
- **spark-f5ea** (Node 1, head): 192.168.1.X LAN, 192.168.100.10 QSFP
- **spark-771e** (Node 2, worker): 192.168.1.84 LAN, 192.168.100.11 QSFP

## Full Start Sequence

**Order matters. Always start Node 1 first.**

### Step 1: Set QSFP IPs (if not persistent)

On spark-f5ea:
```bash
sudo ip addr add 192.168.100.10/24 dev enp1s0f0np0
```

On spark-771e:
```bash
sudo ip addr add 192.168.100.11/24 dev enp1s0f0np0
```

> These don't persist across reboots until you configure netplan (see Persistent IP section below).

### Step 2: Start Head Node (spark-f5ea)

```bash
export MN_IF_NAME=enp1s0f0np0
export VLLM_IMAGE=nvcr.io/nvidia/vllm:26.02-py3
export VLLM_HOST_IP=$(ip -4 addr show $MN_IF_NAME | awk '/inet / && !/169.254/ {print $2}' | cut -d/ -f1)
bash run_cluster.sh $VLLM_IMAGE $VLLM_HOST_IP --head ~/.cache/huggingface -e VLLM_HOST_IP=$VLLM_HOST_IP -e UCX_NET_DEVICES=$MN_IF_NAME -e NCCL_SOCKET_IFNAME=$MN_IF_NAME -e OMPI_MCA_btl_tcp_if_include=$MN_IF_NAME -e GLOO_SOCKET_IFNAME=$MN_IF_NAME -e TP_SOCKET_IFNAME=$MN_IF_NAME -e RAY_memory_monitor_refresh_ms=0 -e MASTER_ADDR=$VLLM_HOST_IP
```

Wait for: `Ray runtime started.`

### Step 3: Start Worker Node (spark-771e) — new SSH tab

```bash
export MN_IF_NAME=enp1s0f0np0
export VLLM_IMAGE=nvcr.io/nvidia/vllm:26.02-py3
export HEAD_NODE_IP=192.168.100.10
export VLLM_HOST_IP=$(ip -4 addr show $MN_IF_NAME | awk '/inet / && !/169.254/ {print $2}' | cut -d/ -f1)
bash run_cluster.sh $VLLM_IMAGE $HEAD_NODE_IP --worker ~/.cache/huggingface -e VLLM_HOST_IP=$VLLM_HOST_IP -e UCX_NET_DEVICES=$MN_IF_NAME -e NCCL_SOCKET_IFNAME=$MN_IF_NAME -e OMPI_MCA_btl_tcp_if_include=$MN_IF_NAME -e GLOO_SOCKET_IFNAME=$MN_IF_NAME -e TP_SOCKET_IFNAME=$MN_IF_NAME -e RAY_memory_monitor_refresh_ms=0 -e MASTER_ADDR=$HEAD_NODE_IP
```

Wait for: `Ray runtime started.`

### Step 4: Verify Cluster (spark-f5ea, new SSH tab)

```bash
export VLLM_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^node-[0-9]+')
docker exec $VLLM_CONTAINER ray status
```

Must show: `2.0/2.0 GPU` and 2 active nodes before proceeding.

### Step 5: Serve the Model (spark-f5ea)

```bash
export VLLM_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^node-[0-9]+')
docker exec -it $VLLM_CONTAINER bash -c 'SAFETENSORS_FAST_GPU=1 vllm serve zai-org/GLM-4.5-Air --trust-remote-code --tensor-parallel-size 2 --distributed-executor-backend ray --max-model-len 32768 --enable-auto-tool-choice --tool-call-parser glm45 --reasoning-parser glm45 --compilation-config "{\"cudagraph_mode\": \"PIECEWISE\"}" --host 0.0.0.0 --port 8000'
```

Startup takes ~5-6 minutes. Wait for: `Application startup complete.`

### Step 6: Verify

```bash
curl http://100.87.122.109:8000/v1/models
```

---

## Restart Sequence

When a serve crashes or you need to restart:

1. Ctrl+C the serve process (if still running)
2. `docker stop $VLLM_CONTAINER` on spark-f5ea — **this also kills Node 2's container**
3. On spark-771e, confirm container is gone: `docker ps`
4. Restart head (Step 2 above)
5. Restart worker (Step 3 above) — new SSH tab, don't close the head tab
6. Verify 2 GPUs (Step 4)
7. Serve (Step 5)

> **Key rule**: Stopping the head node kills the worker. Always restart head first, then worker.

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

## Systemd Auto-start (optional)

Copy service files to both nodes:

```bash
# From Mac Studio
scp ~/dotfiles/ray/systemd/ray-head.service soypete@spark-f5ea:/tmp/
scp ~/dotfiles/ray/systemd/vllm-serve.service soypete@spark-f5ea:/tmp/
scp ~/dotfiles/ray/start-head.sh soypete@spark-f5ea:~/start-head.sh
ssh soypete@spark-f5ea 'sudo mv /tmp/ray-head.service /etc/systemd/system/ && sudo mv /tmp/vllm-serve.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable ray-head vllm-serve'

scp ~/dotfiles/ray/systemd/ray-worker.service soypete@spark-771e:/tmp/
scp ~/dotfiles/ray/start-worker.sh soypete@spark-771e:~/start-worker.sh
ssh soypete@spark-771e 'sudo mv /tmp/ray-worker.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable ray-worker'
```

> **Note**: The worker service has no dependency on the head service (different machine), so it will retry on failure until the head is up. Set static IPs via netplan first, otherwise the QSFP interface won't have an IP on boot.

---

## Troubleshooting

### "Node type must be --head or --worker"
Variables are empty. Set them explicitly before running `run_cluster.sh`.

### "Failed to connect to GCS at 192.168.100.10:6379"
Head node isn't running yet, or QSFP interface has no IP. Check:
```bash
ip addr show enp1s0f0np0   # should show 192.168.100.x
docker ps                  # head container should be running on spark-f5ea
```

### Ray shows 1 GPU instead of 2
Node 2's container started without GPU access, or it's still connected from a previous crashed session. Restart both containers.

### "Current node has no GPU available"
GPU is still reserved by a previous placement group. Restart the cluster (docker stop both containers, restart head, restart worker).

### CUDA launch failure on Node 2 during weight load
Model wasn't pre-cached on Node 2. Download first:
```bash
export VLLM_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^node-[0-9]+')
docker exec -it $VLLM_CONTAINER bash -c 'huggingface-cli download zai-org/GLM-4.5-Air'
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

## Model Notes

| Model | Status | Notes |
|---|---|---|
| `zai-org/GLM-4.5-Air` | ✅ Working | 99.6GB, PIECEWISE required, glm45 parser |
| `zai-org/GLM-4.7-Flash` | ❌ Blocked | Needs transformers>=5.x, incompatible with 26.02-py3 |
| `QuantTrio/MiniMax-M2.5-AWQ` | 🔄 Testing | AWQ marlin works, architecture loads, GPU reservation issue |
| `Qwen/Qwen2.5-Coder-32B-Instruct` | 🔜 Candidate | Smaller, more KV cache headroom |
