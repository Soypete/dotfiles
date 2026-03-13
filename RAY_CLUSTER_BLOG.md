# From Exo to Ray: Running GLM-4.5-Air Across Two DGX Sparks

After my experience trying to run a distributed AI cluster with [exo](https://github.com/exo-explore/exo), I switched to [Ray](https://www.ray.io/) + [vLLM](https://docs.vllm.ai). Ray is battle-tested distributed computing infrastructure, originally built for ML workloads at scale. Here is what actually happened.

---

## Why I Moved Away from Exo

The exo experiment had a fundamental problem: exo only supports MLX-format models, which means Apple Silicon only. My two DGX Spark nodes run NVIDIA GPUs — exo couldn't use them at all. I was paying for the compute and getting nothing out of it.

The more I dug in, the clearer it became that exo is a hobbyist tool for running models across Apple Silicon devices. The DGX Sparks needed something that spoke CUDA.

---

## Why MiniMax-M2.5? (And Why I Ended Up on GLM-4.5-Air)

MiniMax-M2.5 was the original target. It's a coding-focused model trained on over 10 languages — Go, C, C++, TypeScript, Rust, Kotlin, Python, Java, JavaScript, PHP, Lua, Dart, and Ruby — across more than 200,000 real-world environments. The benchmark numbers were compelling:

- **On Droid**: 79.7 (M2.5) vs 78.9 (Opus 4.6)
- **On OpenCode**: 76.1 (M2.5) vs 75.9 (Opus 4.6)

On par with Opus 4.6 on agentic coding tasks. And I can run it locally on hardware I already own.

The catch: MiniMax-M2.5-AWQ uses an architecture (`TransformersForCausalLM`) that vLLM doesn't natively support yet. Even the latest NVIDIA vLLM container (`26.02-py3`) falls back to a Transformers implementation that fails to initialize.

So I switched to **GLM-4.5-Air** from ZAI. It's natively supported by vLLM, loads cleanly across both nodes (~99.6GB per node with tensor parallelism), and leaves ~8GB per node for KV cache. For a single-user coding assistant, that's plenty.

---

## Why Ray + vLLM?

- **CUDA-native**: vLLM is built for NVIDIA GPUs, which is what the Sparks have.
- **Tensor parallelism**: Split model weights across both nodes via Ray's distributed runtime.
- **OpenAI-compatible API**: Drop-in replacement for any OpenAI API client.
- **Production maturity**: This stack runs in production at companies like Anyscale, OpenAI, and others.
- **NVIDIA's official recommendation**: NVIDIA's own DGX Spark playbook uses exactly this stack.

---

## The Hardware

- **2x NVIDIA DGX Spark**: Each node has a Grace Blackwell GB10 GPU, connected via QSFP cable on `enp1s0f0np0` using Ubiquiti networking.
- **Mac Studio (M2 Ultra)**: Orchestration/client machine on the same LAN.

The two Sparks are connected directly via QSFP for high-bandwidth inter-node communication. This is critical for tensor parallelism — you don't want model weights crossing a slow link.

---

## The Setup

### Step 1: Connect the Sparks

Follow NVIDIA's [Connect Two Sparks](https://build.nvidia.com/spark) playbook. This covers:

- Physical QSFP cable connection
- Network interface configuration on `enp1s0f0np0`
- Passwordless SSH between nodes
- Connectivity verification

### Step 2: Download the Cluster Script

On **both nodes**:

```bash
wget https://raw.githubusercontent.com/vllm-project/vllm/refs/heads/main/examples/online_serving/run_cluster.sh
chmod +x run_cluster.sh
```

### Step 3: Pull the NVIDIA vLLM Image

On **both nodes**:

```bash
# First time only — add your user to the docker group
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker

docker pull nvcr.io/nvidia/vllm:26.02-py3
export VLLM_IMAGE=nvcr.io/nvidia/vllm:26.02-py3
```

### Step 4: Start the Ray Head Node (Node 1)

```bash
export MN_IF_NAME=enp1s0f0np0
export VLLM_HOST_IP=$(ip -4 addr show $MN_IF_NAME | awk '/inet / && !/169.254/ {print $2}' | cut -d/ -f1)

echo "Using interface $MN_IF_NAME with IP $VLLM_HOST_IP"

bash run_cluster.sh $VLLM_IMAGE $VLLM_HOST_IP --head ~/.cache/huggingface \
  -e VLLM_HOST_IP=$VLLM_HOST_IP \
  -e UCX_NET_DEVICES=$MN_IF_NAME \
  -e NCCL_SOCKET_IFNAME=$MN_IF_NAME \
  -e OMPI_MCA_btl_tcp_if_include=$MN_IF_NAME \
  -e GLOO_SOCKET_IFNAME=$MN_IF_NAME \
  -e TP_SOCKET_IFNAME=$MN_IF_NAME \
  -e RAY_memory_monitor_refresh_ms=0 \
  -e MASTER_ADDR=$VLLM_HOST_IP
```

### Step 5: Start the Ray Worker Node (Node 2)

```bash
export MN_IF_NAME=enp1s0f0np0
export VLLM_HOST_IP=$(ip -4 addr show $MN_IF_NAME | awk '/inet / && !/169.254/ {print $2}' | cut -d/ -f1)
export HEAD_NODE_IP=<NODE_1_IP_ADDRESS>  # replace with Node 1's QSFP IP

bash run_cluster.sh $VLLM_IMAGE $HEAD_NODE_IP --worker ~/.cache/huggingface \
  -e VLLM_HOST_IP=$VLLM_HOST_IP \
  -e UCX_NET_DEVICES=$MN_IF_NAME \
  -e NCCL_SOCKET_IFNAME=$MN_IF_NAME \
  -e OMPI_MCA_btl_tcp_if_include=$MN_IF_NAME \
  -e GLOO_SOCKET_IFNAME=$MN_IF_NAME \
  -e TP_SOCKET_IFNAME=$MN_IF_NAME \
  -e RAY_memory_monitor_refresh_ms=0 \
  -e MASTER_ADDR=$HEAD_NODE_IP
```

### Step 6: Verify the Cluster

```bash
# On Node 1 — find the running container and check Ray status
export VLLM_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^node-[0-9]+')
docker exec $VLLM_CONTAINER ray status
```

Expected: 2 nodes, GPU resources available.

### Step 7: Pre-download the Model on Both Nodes

**Do this before serving.** If the model isn't cached on Node 2, vLLM will download it during the serve command while simultaneously loading weights into GPU memory. That memory pressure causes a CUDA launch failure on Node 2. Download first, serve second.

```bash
# On Node 1
docker exec -it $VLLM_CONTAINER /bin/bash -c 'huggingface-cli login'
docker exec -it $VLLM_CONTAINER /bin/bash -c 'huggingface-cli download zai-org/GLM-4.5-Air'

# SSH to Node 2, find its container, and download there too
ssh soypete@spark-771e
export VLLM_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^node-[0-9]+')
docker exec -it $VLLM_CONTAINER /bin/bash -c 'huggingface-cli login'
docker exec -it $VLLM_CONTAINER /bin/bash -c 'huggingface-cli download zai-org/GLM-4.5-Air'
```

### Step 8: Serve the Model

Run this from Node 1's container:

```bash
docker exec -it $VLLM_CONTAINER bash -c 'SAFETENSORS_FAST_GPU=1 vllm serve zai-org/GLM-4.5-Air --trust-remote-code --tensor-parallel-size 2 --distributed-executor-backend ray --max-model-len 32768 --enable-auto-tool-choice --tool-call-parser glm45 --reasoning-parser glm45 --compilation-config "{\"cudagraph_mode\": \"PIECEWISE\"}" --host 0.0.0.0 --port 8000'
```

> **`--compilation-config '{"cudagraph_mode": "PIECEWISE"}'` is required** on Grace Blackwell (GB10). Without it, vLLM uses full CUDA graph capture, which fails with `CUDA error: unspecified launch failure` during MoE weight loading. PIECEWISE mode captures graphs per-operation instead of the whole forward pass.

Startup takes about 5-6 minutes: ~2.5 minutes to load weights across both nodes, then ~2 minutes for torch.compile and CUDA graph capture.

### Step 9: Test It

```bash
curl http://localhost:8000/v1/models

curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "zai-org/GLM-4.5-Air",
    "messages": [{"role": "user", "content": "Write a haiku about a GPU cluster"}],
    "max_tokens": 64
  }'
```

---

## What About Llama 3.1 405B?

It technically works, but NVIDIA warns it has insufficient memory headroom for production use. You can run it with aggressive constraints:

```bash
vllm serve hugging-quants/Meta-Llama-3.1-405B-Instruct-AWQ-INT4 \
  --tensor-parallel-size 2 --max-model-len 64 --gpu-memory-utilization 0.9 \
  --max-num-seqs 1 --max_num_batched_tokens 64
```

`--max-model-len 64` is not a typo. That is 64 tokens of context. Not useful for anything real. Treat 405B as a proof of concept on this hardware, not a production option.

---

## Monitoring

Ray ships a dashboard at `http://<head-node-ip>:8265`. GPU utilization per node via:

```bash
docker exec $VLLM_CONTAINER nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

---

## Exo vs Ray: The Honest Comparison

| | Exo | Ray + vLLM |
|---|---|---|
| GPU support | Apple Silicon / MLX only | NVIDIA CUDA (what the Sparks actually have) |
| Setup complexity | Low | Medium |
| Model format | MLX | HuggingFace (GGUF, safetensors, AWQ, FP8) |
| 70B model across 2 nodes | No | Yes, with tensor parallelism |
| Production maturity | Early-stage | High |
| API compatibility | OpenAI-compatible | OpenAI-compatible |
| NVIDIA official support | No | Yes |

The honest answer: exo was the wrong tool for this hardware. Ray + vLLM is what NVIDIA actually recommends for the Sparks, and it shows.

---

## Debugging: What Actually Went Wrong

Getting the cluster running was not as clean as the playbook made it look. Here's what actually happened.

### Wrong network interface

The NVIDIA playbook says to use `enp1s0f1np1`. On my Sparks, that interface exists but is `(Down)`. The correct one is `enp1s0f0np0`. Check yours with:

```bash
ibdev2netdev
```

Use whichever shows `(Up)`.

### Interface has no IP

The QSFP interface had a link-local `169.254.x.x` address but no routable IP. Had to assign one manually:

```bash
sudo ip addr add 192.168.100.10/24 dev enp1s0f0np0  # Node 1
sudo ip addr add 192.168.100.11/24 dev enp1s0f0np0  # Node 2
```

### grep -oP not available

The playbook uses `grep -oP` to extract the IP. That flag is not available on the Sparks. Use `awk` instead:

```bash
export VLLM_HOST_IP=$(ip -4 addr show $MN_IF_NAME | awk '/inet / && !/169.254/ {print $2}' | cut -d/ -f1)
```

### vLLM 0.11.0 does not support MiniMax-M2.5

The `25.11-py3` NVIDIA container ships vLLM `0.11.0+582e4e37.nv25.11.cu130`. MiniMax-M2.5 was released after this build. The error looks like:

```
TransformersForCausalLM has no vLLM implementation, falling back to Transformers implementation
RuntimeError: Engine core initialization failed.
```

**Fix: use the `26.02-py3` container instead:**

```bash
docker pull nvcr.io/nvidia/vllm:26.02-py3
export VLLM_IMAGE=nvcr.io/nvidia/vllm:26.02-py3
```

Even with `26.02-py3`, MiniMax-M2.5-AWQ still fails — the `TransformersForCausalLM` architecture isn't natively supported. That's why I switched to GLM-4.5-Air. Get the latest container from the [NVIDIA NGC catalog](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/vllm).

### CUDA launch failure on Node 2 during weight load

Node 1 loaded fine. Node 2 crashed with:

```
torch.AcceleratorError: CUDA error: unspecified launch failure
File "fused_moe/layer.py", line 1330, in _load_w13
    expert_data.copy_(loaded_weight)
```

Two things caused this:

1. **Model not pre-cached on Node 2**: vLLM was downloading the model (27 minutes) while simultaneously trying to load weights into GPU memory. The memory pressure triggered the CUDA error. Fix: download first with `huggingface-cli download` before running the serve command.

2. **Full CUDA graph capture fails on GB10 with MoE models**: vLLM's default full cudagraph mode tries to trace the entire forward pass, including fused MoE kernels, which fails on Grace Blackwell. Fix: `--compilation-config '{"cudagraph_mode": "PIECEWISE"}'`

### Line wrapping in terminal breaks long commands

iTerm2 wraps long commands visually and pastes them with line breaks, which bash interprets as syntax errors. Solution: write long commands to a script file and run that instead.

```bash
# On Mac Studio — write the serve command to a script
cat > ~/dotfiles/ray/serve-glm.sh << 'EOF'
SAFETENSORS_FAST_GPU=1 vllm serve zai-org/GLM-4.5-Air --trust-remote-code --tensor-parallel-size 2 --distributed-executor-backend ray --max-model-len 32768 --enable-auto-tool-choice --tool-call-parser glm45 --reasoning-parser glm45 --compilation-config '{"cudagraph_mode": "PIECEWISE"}' --host 0.0.0.0 --port 8000
EOF

# Copy to Spark and run inside container
scp ~/dotfiles/ray/serve-glm.sh soypete@spark-f5ea:/tmp/serve-glm.sh
ssh soypete@spark-f5ea "docker cp /tmp/serve-glm.sh $VLLM_CONTAINER:/tmp/serve-glm.sh"
ssh soypete@spark-f5ea "docker exec -it $VLLM_CONTAINER bash /tmp/serve-glm.sh"
```

### Missing MoE tuning config for NVIDIA GB10

During startup you'll see:

```
WARNING Using default MoE config. Performance might be sub-optimal!
Config file not found at [.../configs/E=128,N=704,device_name=NVIDIA_GB10.json]
```

vLLM has pre-tuned Triton kernel configs for known GPUs but not the GB10 yet. The server works fine — it's a performance warning. To generate a tuned config after the cluster is running:

```bash
docker exec -it $VLLM_CONTAINER python \
  /usr/local/lib/python3.12/dist-packages/vllm/model_executor/layers/fused_moe/benchmark_moe.py \
  --dtype bfloat16 --model zai-org/GLM-4.5-Air --tp-size 2
```

This takes 30-60 minutes and writes the config file automatically.

---

## What's Next

- Automating cluster startup (launchd or systemd on both Sparks)
- Generating the GB10 MoE tuning config for better throughput
- Benchmarking actual tokens/sec
- MiniMax-M2.5 once vLLM adds native `TransformersForCausalLM` support

---

*Follow along live at [twitch.tv/soypete01](https://twitch.tv/soypete01)*
