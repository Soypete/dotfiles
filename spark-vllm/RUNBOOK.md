# Spark vLLM Cluster Runbook

Two-node NVIDIA Spark cluster serving an OpenAI-compatible API via
`eugr/spark-vllm-docker` (which manages the containers, the Ray cluster, and
`vllm serve`). This replaces the hand-rolled `ray/` scripts and their three
separate systemd units with one `vllm-cluster.service`.

**Models are switchable** — see "Switching models" below. MiniMax-M2.5-AWQ is the
known-good fallback; DeepSeek-V4-Flash-0731 is the larger 284B MoE option.

**Endpoint:** port 8000 on the head node — consumed by `opencode/opencode.json`.
The tailnet address depends on which tailnet the client is on:
- haikei tailnet: `http://100.87.122.108:8000/v1`
- other tailnet:  `http://100.87.122.109:8000/v1`
Both are the same machine (spark-f5ea); it presents the same SSH host key on each.

## Hardware
- **spark-f5ea** (Node 1, head): 192.168.1.9 LAN, 192.168.100.10 QSFP
- **spark-771e** (Node 2, worker): 192.168.1.84 LAN, 192.168.100.11 QSFP

**Worker address:** use `192.168.100.11` (QSFP) or `192.168.1.84` (LAN). The
link-local `169.254.91.57` used by older versions of these scripts **no longer
answers** (verified 2026-08-31) — it was corrected in `cleanup-containers.sh` and
`hf-download-gguf.sh`.

**`spark-f5ea` may resolve to the LAN address via mDNS** rather than the tailnet,
in which case ssh fails with `Permission denied (publickey)`. Use the tailnet IP.

## Deploying these scripts to the Sparks

The Sparks have **no dotfiles checkout**. The scripts in this directory are
authored on the Mac and scp'd to `/home/soypete/` on the head node, which is why
`vllm-cluster.service` references `/home/soypete/start-cluster.sh` rather than a
dotfiles path. Re-deploy after editing any of them:

```bash
# from the Mac, in ~/dotfiles/spark-vllm
scp start-cluster.sh start-cluster-deepseek.sh start-cluster-gguf.sh \
    cleanup-containers.sh hf-download-gguf.sh spark-f5ea:/home/soypete/
ssh spark-f5ea 'chmod +x /home/soypete/*.sh'

# systemd unit (only when the unit itself changed)
scp systemd/vllm-cluster.service spark-f5ea:/tmp/
ssh spark-f5ea 'sudo mv /tmp/vllm-cluster.service /etc/systemd/system/ \
                && sudo systemctl daemon-reload'

# model-selection env file (first install, or when switching models)
scp systemd/vllm-cluster.env.example spark-f5ea:/tmp/
ssh spark-f5ea 'sudo mv /tmp/vllm-cluster.env.example /etc/default/vllm-cluster'
```

Editing the copy on the Spark directly will be silently overwritten by the next
deploy — change it here and re-scp.

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

### Boot hangs on "Waiting for creating a placement group" with 1 GPU
QSFP static IPs are gone (interfaces fell back to link-local 169.254.x), so
`launch-cluster.sh` autodiscovery can't find the worker and boots solo.
Confirmed cause of the 2026-07-01 outage — the netplan persistence step had
never been applied. Check `ip addr show enp1s0f0np0` on both nodes: if there's
no 192.168.100.x address, apply the "Persistent IP Configuration" section
above on both nodes, then `sudo systemctl restart vllm-cluster`.
(Single-line variant, since pasted heredocs wrap badly:
`sudo bash -c 'printf "network:\n  version: 2\n  ethernets:\n    enp1s0f0np0:\n      addresses:\n        - 192.168.100.10/24\n" > /etc/netplan/99-qsfp-static.yaml && chmod 600 /etc/netplan/99-qsfp-static.yaml && netplan apply'`
— use `.11` on the worker.)

### Ray shows 1 GPU instead of 2
Node 2's container started without GPU access, or it's still connected from a previous crashed session. Restart both containers.

### "Current node has no GPU available"
GPU is still reserved by a previous placement group. `launch-cluster.sh exec` won't fix this because it skips container restart when containers are already running. You must manually stop and remove containers on both nodes first:
```bash
docker stop vllm_node && docker rm vllm_node
ssh 192.168.100.11 'docker stop vllm_node && docker rm vllm_node'
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
OOM kill on Node 2 during a large context request.

Historical note: this was routine when the cluster served `--max-model-len 32768`
at `--gpu-memory-utilization 0.7` with the old `ray/start-head.sh` scripts, where
anything over ~16k tokens could tip Node 2 over. The current AWQ config serves
the full `--max-model-len 128000` (~58GB/node of weights at 0.7 util leaves
~30GB/node of KV cache) and does not hit this at normal OpenCode context sizes.

If it recurs, check in this order:
1. `vllm serve` startup log — trust the printed `GPU KV cache size: N tokens`
   over any estimate here. If N is far below `--max-model-len`, KV cache is the
   binding constraint.
2. Concurrency, not context length: several simultaneous long requests share one
   KV pool. Lower `--max-num-seqs` before lowering `--max-model-len`.
3. Only then reduce `--max-model-len`.

### Context length errors from OpenCode
OpenCode compaction sends large context windows. The client is sized to stay
inside the server's window with headroom — `opencode/opencode.json` sets
`context: 100000` + `output: 24000` = 124K against the server's 128K
`--max-model-len`. Keep that sum under `--max-model-len`; if you lower the
server's window, lower the client limits to match or compaction will fail
mid-session. Starting a fresh OpenCode session also reduces context size.

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

**`hf-download.sh` requires `uvx`**, which lives in `~/.local/bin` and is *not* on
PATH for non-login shells (systemd, tmux, `ssh host 'cmd'`). Without it the script
exits with "Error: 'uvx' command not found." Prefix with:

```bash
PATH="$HOME/.local/bin:$PATH" ./hf-download.sh ...
```

`start-cluster-deepseek.sh` exports this itself. The same PATH quirk is handled in
`hf-download-gguf.sh` by explicit CLI discovery.

---

## Recipes (upstream) — the preferred path for new models

Upstream `eugr/spark-vllm-docker` ships a **recipe system** that supersedes
hand-written serve commands for new models. Each `recipes/*.yaml` declares the
model, container image, build args, mods, env vars, and the full serve command:

```bash
cd ~/spark-vllm-docker
./run-recipe.sh --list                       # what's available
./run-recipe.sh <recipe> --dry-run -n <head>,<worker>   # show generated command
./run-recipe.sh <recipe> --build-only -n ... # build/copy container only
./run-recipe.sh <recipe> --download-only -n ...  # download + copy weights
./run-recipe.sh <recipe> -n <head>,<worker>  # serve
```

Because the recipe is the source of truth, upstream fixes arrive with a `git pull`
rather than needing local edits. **This is why no fork was needed** — `container:`,
`env:`, and `mods:` are already per-recipe.

**Keep the checkout current.** As of 2026-08-31 the local clone was 309 commits
behind, which predated every DeepSeek/GLM recipe. Rollback tag before that update:
`pre-upgrade-2026-08-31` (= `d609fec`).

---

## DeepSeek-V4-Flash-0731

284B-total / 13B-active MoE, ~167GB of FP4/FP8-mixed safetensors (**not** GGUF —
see the GGUF post-mortem below). `cluster_only: true` — one GB10's 128GB cannot
hold it, so it must run tp=2 across both nodes.

```bash
cd ~/spark-vllm-docker
PATH="$HOME/.local/bin:$PATH" ./run-recipe.sh deepseek-v4-flash-0731 \
    -n 192.168.100.10,192.168.100.11
```

Or via systemd, with `START_SCRIPT=/home/soypete/start-cluster-deepseek.sh` in
`/etc/default/vllm-cluster`.

The recipe uses container `vllm-node-b12x` (built via `build-and-copy.sh
--exp-b12x`, which pulls the prebuilt `eugr/spark-vllm-b12x` runner), the
`instanttensor-hybrid-draft-loader` mod, `dspark` speculative decoding, and the
SM121 env block (`CUTE_DSL_ARCH=sm_121a`, `VLLM_USE_B12X_*`).

### Verified working — 2026-08-31

First successful bring-up. Measured on the running server:

| Metric | Value |
|---|---|
| `max_model_len` (`auto` resolved) | **874,496** |
| Model load | 81.34 GiB/node, ~80 s |
| GPU KV cache | 959,451 tokens (1.10x concurrency at max len) |
| Available KV memory | 10.34 GiB/node |
| Generation throughput | **~64 tok/s** (193 tok, single stream, warm) |
| Startup wall time | ~4.5 min (weights → `Application startup complete`) |

Verified: plain completion, `deepseek_v4` reasoning parser (reasoning split from
content), tool calling (`finish_reason: tool_calls`, correct args), and the
endpoint over the tailnet at `http://100.87.122.108:8000/v1`.

**OpenCode limits** are set to 262144 context / 32000 output — deliberately well
under `max_model_len`. The whole KV pool is only ~1.1x one max-length request, so
a single 874K request would starve everything else. Raise only if you accept
serialized requests.

Benign log noise during startup: `No available shared memory broadcast block
found in 60 seconds` (appears during compilation) and a `gpu_memory_utilization`
CUDA-graph-profiling advisory.

**`vm.swappiness=0` is required on both nodes** — the GB10 UVM driver can livelock
if the kernel pages vLLM out during a large weight load. It does not survive reboot
unless persisted:

```bash
echo "vm.swappiness=0" | sudo tee /etc/sysctl.d/99-vllm-swappiness.conf
sudo sysctl -w vm.swappiness=0
```

### Switching models

Only one model runs at a time — 167GB of DeepSeek weights and MiniMax's ~58GB/node
cannot coexist in 128GB/node.

```bash
sudo systemctl stop vllm-cluster
sudo vi /etc/default/vllm-cluster     # set START_SCRIPT
sudo systemctl start vllm-cluster
```

`vllm-cluster.service` defaults to MiniMax when `/etc/default/vllm-cluster` is
absent. `TimeoutStartSec` is 1800 to accommodate DeepSeek's longer load.

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
  --load-format fastsafetensors \
  --enable-auto-tool-choice --tool-call-parser minimax_m2 \
  --reasoning-parser minimax_m2
```

This mirrors `start-cluster.sh` exactly. Two earlier discrepancies in this runbook
are now resolved: the command here previously showed
`--compilation-config '{"cudagraph_mode": "PIECEWISE"}'` (not used by the script;
see the Node 2 CUDA note below for when to add it) and
`--reasoning-parser minimax_m2_append_think` (the script uses `minimax_m2`).

Note upstream's `recipes/minimax-m2.5-awq.yaml` has since moved to
`--load-format instanttensor` and `gpu_memory_utilization: 0.8`.

---

## GGUF (experimental)

Serving `unsloth/MiniMax-M3-GGUF` (UD-IQ4_NL) via vLLM's GGUF path. Treat as an
experiment: vLLM docs mark GGUF "highly experimental and under-optimized", it
lives in an out-of-tree plugin (`vllm-gguf-plugin`), and there is an open RFC
to deprecate it. Don't expect AWQ-level throughput.

### Known constraints
- **Single-file only** — unsloth quants are sharded, so shards are merged with
  llama.cpp's `llama-gguf-split --merge` (handled by `hf-download-gguf.sh`).
- **Hardcoded architecture list** — the GGUF loader remaps a fixed set of model
  types. `minimax_m2` is in the list; **M3 is unverified**. If serve fails with
  an unsupported-architecture error, M3 GGUF isn't in vLLM yet.
- **Quant choice = context budget** — M3 is ~426B params. With `-tp 2` each
  node holds half the weights; at 0.90 util vLLM gets ~115GB of each 128GB
  node. What's left after weights is KV cache (~100–250KB/token fp16, split
  across nodes). Fit table (2026-07-01):

  | Quant | Total | Weights/node | KV headroom/node | Realistic context |
  |---|---|---|---|---|
  | UD-IQ4_NL | 212GB | ~106GB | ~9GB | ~16–32K — rejected, too small for OpenCode |
  | UD-Q3_K_XL | 195GB | ~97GB | ~17GB | ~32–64K |
  | **UD-IQ3_XXS** | **159GB** | **~79GB** | **~35GB** | **~128K — chosen** |

  For comparison, M2.5-AWQ today: ~58GB/node weights at 0.7 util → ~30GB/node
  KV → serves 128K. vLLM prints the exact "GPU KV cache size: N tokens" at
  startup — trust that over this table.
- **Tokenizer from the base model** — `--tokenizer MiniMaxAI/MiniMax-M3`; GGUF
  tokenizer conversion is unstable for large vocabs. Garbage output usually
  means a tokenizer problem.

### Prerequisites (once, on spark-f5ea)
```bash
pip install -U 'huggingface_hub[cli]'
git clone https://github.com/ggml-org/llama.cpp ~/code/llama.cpp
cd ~/code/llama.cpp && cmake -B build && cmake --build build --target llama-gguf-split
```
Disk: ~220GB of shards + ~220GB merged file transiently per node.

### Flow
```bash
./hf-download-gguf.sh                  # download + merge + rsync to worker (hours)
sudo systemctl stop vllm-cluster
./cleanup-containers.sh
./start-cluster-gguf.sh                # run in tmux, watch weight load
curl http://100.87.122.109:8000/v1/models
```

### Result of the 2026-07-01 attempt: BLOCKED — vLLM cannot serve MiniMax-M3 GGUF

The download/merge/distribute pipeline works (149GB UD-IQ3_XXS merged and on
both nodes at `~/.cache/huggingface/gguf/MiniMax-M3-GGUF/`). Serving failed,
and the block is fundamental, not a config issue:

1. `vllm-gguf-plugin` 0.0.x fails to import in the nvcr 26.02 container
   (needs a newer vLLM API than 0.17.x has). Not needed anyway — 0.17.x still
   has in-tree GGUF.
2. In-tree GGUF rejected it: `GGUF model with architecture minimax-m3 is not
   supported yet`. The container's transformers (4.57.6) GGUF converter has
   NO minimax archs at all (so M2.5-GGUF also fails here), and its vLLM has
   no `MiniMaxM3ForCausalLM` class (build predates M3).
3. Upgrading doesn't help: the newest vllm-gguf-plugin's adapter remaps
   `minimax_m2` only — no `minimax-m3` anywhere in vLLM's GGUF stack as of
   July 2026.

**Paths forward for M3 on the Sparks:**
- **llama.cpp** (`llama-server` + `rpc-server` on the worker) — llama.cpp
  supports minimax-m3 GGUF; OpenAI-compatible API; the merged file is already
  in place on both nodes. Different stack from the vLLM/Ray setup.
- **Wait/contribute**: minimax-m3 support in vllm-gguf-plugin's weights
  adapter (upstream contribution opportunity alongside the eugr one).
- Lessons that DO carry over to other GGUF models on this cluster:
  serve the *container* path (`/root/.cache/huggingface/...`), skip the
  plugin on nvcr 26.02, single-file merge required, worker rsync via
  192.168.100.11. Supported GGUF archs in this container: qwen2/qwen2moe/
  qwen3/qwen3_moe + llama-family only.

systemd (`vllm-cluster.service`) never points at the GGUF script; model choice is
now the `START_SCRIPT` variable in `/etc/default/vllm-cluster`.

### 2026-08-31: the same block applies to DeepSeek GGUF — use the native checkpoint

Asked to serve `unsloth/DeepSeek-V4-Flash-GGUF/UD-IQ4_XS` (138GB) on vLLM. **Same
root cause, do not retry:** vLLM's GGUF loader depends on `transformers`' GGUF
converter knowing the architecture. DeepSeek-V4's arch is `deepseek4`; even the
much older `deepseek2` is still unsupported
(<https://github.com/vllm-project/vllm/issues/15277>). Unsloth's own model card
directs GGUF users to llama.cpp or Unsloth Studio, not vLLM.

**The fix is to not use GGUF at all.** vLLM has day-0 native support for
DeepSeek-V4-Flash, and upstream ships `recipes/deepseek-v4-flash-0731.yaml` for
2x DGX Spark at tp=2 — see the DeepSeek section above. The native checkpoint is
~167GB of FP4/FP8-mixed safetensors, *smaller* than the 138GB GGUF once you
account for GGUF needing a merged single file plus its shards during merge.

**General rule for this cluster:** GGUF on vLLM is a dead end for any arch the
container's `transformers` doesn't know. Check for a native/AWQ/NVFP4 checkpoint
and an upstream recipe *first*; reach for GGUF only via llama.cpp.

Also note the vLLM GGUF docs' own caveats (single-file only, use `--tokenizer`
from the base model, "highly experimental and under-optimized"):
<https://docs.vllm.ai/en/latest/features/quantization/gguf.html>

### Throughput tuning
Baseline first, one knob at a time. Benchmark from inside the head container:
```bash
vllm bench serve --host localhost --port 8000 --num-prompts 50
```
Knobs in order of expected payoff:
- `--max-num-batched-tokens` 8192 → 16384/32768 (prefill throughput)
- `--max-num-seqs` start 8–16, raise until KV-cache preemption warnings
- `GPU_MEM_UTIL` 0.90 → 0.92/0.94 if stable (more KV cache); back off on OOM
- `MAX_MODEL_LEN` as small as real usage allows (freed KV space → batch size)
- confirm PIECEWISE cudagraph captures succeed in logs

Results:

| Config | req/s | TTFT | output tok/s |
|---|---|---|---|
| (baseline defaults) | | | |

---

## Model Notes

| Model | Status | Notes |
|---|---|---|
| `QuantTrio/MiniMax-M2.5-AWQ` | ✅ Working | eugr/spark-vllm-docker, minimax_m2 parser, PIECEWISE required |
| `unsloth/MiniMax-M3-GGUF` (UD-IQ3_XXS) | ❌ Blocked on vLLM | no minimax-m3 GGUF support anywhere in vLLM (in-tree or plugin) as of 2026-07; file staged on both nodes; llama.cpp is the viable route |
| `zai-org/GLM-4.5-Air` | ❌ Not working | 99.6GB, never got working on dual Spark |

## Model Selection Resources

- **LiveBench** (open-weight, high unseen bias filter): https://livebench.ai/#/?openweight=true&highunseenbias=true
  - Use this to compare open-weight models on benchmarks with low data contamination risk
  - Filter by context length and task type to find candidates for this cluster
