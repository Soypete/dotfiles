# From Exo to Ray: Running MiniMax-M2.5 Across Two DGX Sparks

After my experience trying to run a distributed AI cluster with [exo](https://github.com/exo-explore/exo), I switched to [Ray](https://www.ray.io/) + [vLLM](https://docs.vllm.ai). Ray is battle-tested distributed computing infrastructure, originally built for ML workloads at scale. Here is what actually happened.

---

## Why I Moved Away from Exo

The exo experiment had a fundamental problem: exo only supports MLX-format models, which means Apple Silicon only. My two DGX Spark nodes run NVIDIA GPUs — exo couldn't use them at all. I was paying for the compute and getting nothing out of it.

The more I dug in, the clearer it became that exo is a hobbyist tool for running models across Apple Silicon devices. The DGX Sparks needed something that spoke CUDA.

---

## Why MiniMax-M2.5?

MiniMax-M2.5 is a coding-focused model trained on over 10 languages — Go, C, C++, TypeScript, Rust, Kotlin, Python, Java, JavaScript, PHP, Lua, Dart, and Ruby — across more than 200,000 real-world environments. It's built for the full development lifecycle: 0-to-1 system design, 1-to-10 development, 10-to-90 feature iteration, and 90-to-100 code review and testing. Full-stack across Web, Android, iOS, and Windows.

The benchmark numbers are what got my attention. On SWE-Bench Verified using real coding agent harnesses:

- **On Droid**: 79.7 (M2.5) vs 78.9 (Opus 4.6)
- **On OpenCode**: 76.1 (M2.5) vs 75.9 (Opus 4.6)

It performs on par with Opus 4.6 on agentic coding tasks. And I can run it locally on hardware I already own.

The catch: it's a 456B MoE model. The full precision version doesn't fit in my cluster's 222GB. The AWQ 4-bit quantized version from QuantTrio comes in at ~130GB — fits comfortably with ~90GB left for KV cache.

---

## Why Ray + vLLM?

- **CUDA-native**: vLLM is built for NVIDIA GPUs, which is what the Sparks have.
- **Tensor parallelism**: Split a 70B model across both nodes via Ray's distributed runtime.
- **OpenAI-compatible API**: Drop-in replacement for any OpenAI API client.
- **Production maturity**: This stack runs in production at companies like Anyscale, OpenAI, and others.
- **NVIDIA's official recommendation**: NVIDIA's own DGX Spark playbook uses exactly this stack.

---

## The Hardware

- **2x NVIDIA DGX Spark**: Each node has a Grace Blackwell GPU, connected via QSFP cable on a high-speed interface (`enp1s0f0np0`) using Ubiquiti networking.
- **Mac Studio (M2 Ultra)**: Orchestration/client machine on the same LAN.

The two Sparks are connected directly via QSFP for high-bandwidth inter-node communication. This is critical for tensor parallelism — you don't want your model weights crossing a slow link.

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

### Step 7: Download and Serve MiniMax-M2.5-AWQ

Login to Hugging Face inside the container, then download and serve the model:

```bash
docker exec -it $VLLM_CONTAINER /bin/bash -c 'huggingface-cli login'

# Download the model (~130GB)
docker exec -it $VLLM_CONTAINER /bin/bash -c 'huggingface-cli download QuantTrio/MiniMax-M2.5-AWQ'

# Launch with tensor parallelism across both nodes
docker exec -it $VLLM_CONTAINER /bin/bash -c '
  export VLLM_USE_FLASHINFER_MOE_FP16=1
  export VLLM_USE_FLASHINFER_SAMPLER=0
  export OMP_NUM_THREADS=4

  vllm serve QuantTrio/MiniMax-M2.5-AWQ \
    --tensor-parallel-size 2 \
    --enable-expert-parallel \
    --max_model_len 32768 \
    --max-num-seqs 32 \
    --swap-space 16 \
    --gpu-memory-utilization 0.9 \
    --trust-remote-code \
    --host 0.0.0.0 \
    --port 8000'
```

> **Note on model choice**: MiniMax-M2.5 is a 456B MoE model. The AWQ 4-bit quantized version from QuantTrio comes in at ~130GB — fits comfortably in the 222GB combined memory, leaving ~90GB for KV cache and inference overhead. Full precision and GGUF versions don't fit.

### Step 8: Test It

```bash
curl http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "QuantTrio/MiniMax-M2.5-AWQ",
    "prompt": "Write a haiku about a GPU",
    "max_tokens": 32,
    "temperature": 0.7
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

**Fix: use the `26.02-py3` container instead.** It includes MiniMax-M2.5 support out of the box:

```bash
docker pull nvcr.io/nvidia/vllm:26.02-py3
export VLLM_IMAGE=nvcr.io/nvidia/vllm:26.02-py3
```

Get the latest container from the [NVIDIA NGC catalog](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/vllm). The `25.11` container was current when the NVIDIA playbook was written but predates MiniMax-M2.5.

### Line wrapping in terminal breaks long commands

iTerm2 wraps long commands visually and pastes them with line breaks, which bash interprets as syntax errors. Solution: write long commands to a script file and run that instead.

```bash
# On Mac Studio
cat > ~/dotfiles/ray/serve-minimax.sh << 'EOF'
SAFETENSORS_FAST_GPU=1 vllm serve QuantTrio/MiniMax-M2.5-AWQ --trust-remote-code --tensor-parallel-size 2 --distributed-executor-backend ray --max-model-len 32768 --enable-auto-tool-choice --tool-call-parser minimax_m2 --reasoning-parser minimax_m2_append_think --host 0.0.0.0 --port 8000
EOF

# Copy to Spark and run inside container
scp ~/dotfiles/ray/serve-minimax.sh soypete@spark-f5ea:/tmp/serve-minimax.sh
ssh soypete@spark-f5ea "docker cp /tmp/serve-minimax.sh node-23463:/tmp/serve-minimax.sh"
ssh soypete@spark-f5ea "docker exec -it node-23463 bash /tmp/serve-minimax.sh"
```

---

## What's Next

- Confirm MiniMax-M2.5-AWQ serving successfully with nightly vLLM
- Point OpenCode at the Ray cluster endpoint
- Automating cluster startup on the Sparks
- Benchmarking throughput

---

*Follow along live at [twitch.tv/soypete01](https://twitch.tv/soypete01)*
