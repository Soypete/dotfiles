# Spark vLLM Cluster Runbook

Two-node NVIDIA Spark cluster serving an OpenAI-compatible API via
`eugr/spark-vllm-docker` (which manages the containers, the distributed backend,
and `vllm serve`). This replaces the hand-rolled `ray/` scripts and their three
separate systemd units with one `vllm-cluster.service`.

## Current state (2026-09-14)

**Serving `deepseek-ai/DeepSeek-V4-Flash`** — stock `vllm-node` container on
vLLM 0.29.1rc1, `START_SCRIPT=/home/soypete/start-cluster-deepseek-ray.sh`
(recipe `deepseek-v4-flash-safetensors`). Verified: correct answers, 4-way
concurrency, 2k-token prompts, ~1 s latency, `-tp2-` fingerprint, `Worker_TP`
busy on both nodes, zero RDMA errors.

| | |
|---|---|
| max_model_len | 131072 |
| GPU KV cache | 464,928 tokens (23.82 GiB) |
| Max concurrency | **3.55x** at full length (vs 1.10x on the old B12X config) |
| Weights | 75.77 GiB/node of 128 GB |
| gpu_memory_utilization | 0.90 |

**Two things are pinned and must stay that way:**

1. **Kernel `6.11.0-1016-nvidia` on both nodes.** `7.0.0-1019-nvidia` breaks RDMA
   memory registration and takes down multi-node serving entirely — see
   "kernel 7.0.0 breaks RDMA" below. GRUB defaults to 6.11 and the
   `linux-nvidia-hwe-24.04` packages are `apt-mark hold`.
2. **Docker `memlock` unlimited** via `/etc/docker/daemon.json` on both nodes.
   Docker 29 defaults it to 8 MB, which also breaks RDMA — see the memlock
   section below.

**Models are switchable** — see "Switching models" below. MiniMax-M2.5-AWQ is the
known-good fallback (Ray, stock container, weights cached on both nodes);
DeepSeek-V4-Flash-0731 is the B12X/experimental option, whose in-image plugin is
now mismatched against newer vLLM.

**Endpoint:** port 8000 on the head node — consumed by `opencode/opencode.json`.
The tailnet address depends on which tailnet the client is on:
- haikei tailnet: `http://100.87.122.108:8000/v1`
- other tailnet:  `http://100.87.122.109:8000/v1`
Both are the same machine (spark-f5ea); it presents the same SSH host key on each.

That is spark-f5ea's tailscale0 address on the personal tailnet
(`tail6fbc5.ts.net`). The same machine is `100.87.122.108` on the haikeilabs
tailnet, so from a Mac logged into haikeilabs the `.109` address will not ping
even though the box is up and the config is correct. Check which tailnet you are
on (`tailscale status`) before concluding the endpoint address is stale.

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
scp start-cluster.sh start-cluster-deepseek.sh start-cluster-deepseek-ray.sh \
    start-cluster-gguf.sh cleanup-containers.sh hf-download-gguf.sh \
    spark-f5ea:/home/soypete/
ssh spark-f5ea 'chmod +x /home/soypete/*.sh'

# systemd unit (only when the unit itself changed)
scp systemd/vllm-cluster.service spark-f5ea:/tmp/
ssh spark-f5ea 'sudo mv /tmp/vllm-cluster.service /etc/systemd/system/ \
                && sudo systemctl daemon-reload'

# model selector (first install, or when switching the default model profile).
# default/vllm-cluster is the tracked copy of what is deployed;
# systemd/vllm-cluster.env.example documents all three START_SCRIPT options.
scp default/vllm-cluster spark-f5ea:/tmp/
ssh spark-f5ea 'sudo mv /tmp/vllm-cluster /etc/default/vllm-cluster'
```

Editing the copy on the Spark directly will be silently overwritten by the next
deploy — change it here and re-scp.

## Model selection

`vllm-cluster.service` does not hardcode a model. It runs `$START_SCRIPT`, which
comes from `/etc/default/vllm-cluster` (tracked here as `default/vllm-cluster`),
falling back to MiniMax if that file is absent. Only one model runs at a time —
167GB of DeepSeek weights and MiniMax's ~58GB/node cannot share 128GB/node.

| `START_SCRIPT` | Model | Status |
|---|---|---|
| `start-cluster-deepseek.sh` | DeepSeek-V4-Flash-0731 | ✅ current default |
| `start-cluster.sh` | MiniMax-M2.5-AWQ | ✅ known-good fallback |

Switching models means updating **both** ends: `/etc/default/vllm-cluster` on the
Spark and the `ray` provider's model id in `opencode/opencode.json` (both models
are listed there; change the top-level `model` key). The server matches on exact
model id, so a mismatch leaves the endpoint up but returns model-not-found rather
than a connection error.

### DeepSeek-V4-Flash-0731 startup profile (2026-09-08, first successful serve)

~4 minutes cold to `Application startup complete.`:

| Phase | Time |
|---|---|
| Weight load (InstantTensor draft-loader) | 31s + 45s |
| `torch.compile` (AOT cache hit) | 1.8s |
| Profiling/warmup run | 18s |
| DeepSeek V4 mHC kernel warmup | 4.7s |

Served `max_model_len` is **785,152**, and vLLM reports `GPU KV cache size:
861,420 tokens` — but max concurrency at full context is only **1.10x**. One
maximum-length request consumes nearly the entire KV pool, so concurrent requests
queue rather than run in parallel. The client is therefore set to `context:
200000` rather than anything near the ceiling, which leaves real headroom for
concurrency and for OpenCode's compaction behavior.

`SymmMemCommunicator: Device capability 12.1 not supported` during startup is
benign on GB10 — it falls back to a standard communicator.

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

### "Error: No active IB interfaces found." (crash-loop every 60s)

`launch-cluster.sh`/`run-recipe.sh` autodetect the QSFP fabric before starting
vLLM. With no link they exit 1 immediately — the model never loads, nothing ever
binds :8000, and `Restart=on-failure` retries forever. A restart counter in the
hundreds or thousands means this has been looping for days.

**This is a link-layer failure, not the netplan failure below.** Both leave
`enp1s0f0np0` without a `192.168.100.x` address, so `ip addr` alone can't tell
them apart. `carrier` is what separates them:

```bash
cat /sys/class/net/enp1s0f0np0/carrier   # 0 = no physical link, 1 = link up
ip neigh show | grep 192.168.1.84        # INCOMPLETE/FAILED = worker not on the wire
```

- `carrier=0` → the other Spark is off, or the QSFP cable is unseated/failed.
  Config is irrelevant; no amount of `netplan apply` will fix it. Sparks have no
  status LEDs, so confirm from the head node rather than by looking at the box.
- `carrier=1` but no address → genuine netplan problem; see the next section.

Confirmed cause of the 2026-09-06 outage: the worker left the network shortly
after a routine `systemctl restart` (the ExecStop shutdown in the journal is
clean — no OOM, no CUDA error), so the restart's ExecStart had no fabric to
detect and looped 1,665 times over two days.

Note the head node's tailscale0 address (`100.87.122.109`) stays up throughout,
since it is unrelated to the QSFP fabric — the endpoint being unreachable while
the host still pings is expected here, not evidence of a network problem.

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

### Which executor am I actually on? (Ray vs NCCL — check this FIRST)

**Not every model here uses Ray.** The executor comes from the recipe, and the
Ray-specific troubleshooting below only applies to the Ray recipes:

| Recipe / script | Executor | Container |
|---|---|---|
| `minimax-m2.5-awq` (`start-cluster.sh`) | **Ray** (`--distributed-executor-backend ray`) | `vllm-node` |
| `deepseek-v4-flash` (`start-cluster-deepseek-ray.sh`) | recipe says Ray, but vLLM 0.29.1rc1 runs **NCCL** (MultiprocExecutor) anyway | `vllm-node` |
| `deepseek-v4-flash-0731` (`start-cluster-deepseek.sh`) | **NCCL** (MultiprocExecutor) | `vllm-node-b12x` |

Confirm from the running service rather than guessing:

```bash
# Ray path prints RayDistributedExecutor / RayWorkerWrapper;
# NCCL path prints multiproc_executor.py and a tcp:// init method.
journalctl -u vllm-cluster -b | grep -aiE 'multiproc_executor|RayWorkerWrapper|distributed_init_method'
```

On the NCCL path expect `distributed_init_method=tcp://192.168.100.10:29501
backend=nccl` and `world_size=2`. **`ray status` will fail with "Could not find
any running Ray instance" / a GCS timeout on 6379 — that is normal there, not a
fault.** Ranks also log to their own node: `Worker_TP0` appears in the head's
journal, `Worker_TP1` only in `docker logs vllm_node` on the worker.

Quick proof both nodes are really computing (any executor): a completion's
`system_fingerprint` ends in `-tp2-…`, and `ps` on the worker shows a busy
`VLLM::Worker_TP` process holding tens of GB of RSS.

### Ray shows 1 GPU instead of 2
*(Ray recipes only — see the executor table above.)*
Node 2's container started without GPU access, or it's still connected from a previous crashed session. Restart both containers.

### 2026-09-14: kernel 7.0.0 breaks RDMA — DO NOT UPGRADE THE KERNEL

**Kernel `7.0.0-1019-nvidia` cannot serve multi-node on these Sparks.** Every
`vllm serve` dies during worker init with:

```
NCCL WARN Call to ibv_reg_mr_iova2 failed with error Cannot allocate memory
RuntimeError: NCCL error: unhandled system error
```

RDMA memory registration fails inside containers. It affects **both** executors —
NCCL (B12X recipe) *and* Ray (MiniMax recipe) fail identically — so it is below
the executor layer. `6.11.0-1016-nvidia` works; the same configs served all
morning on it.

Ruled out during the investigation (don't re-chase these): wrong `IB_IF`,
orphaned containers, Docker memlock (fixed separately, see below), and
`nvidia-peermem` — that module can't load on 7.0.0 (`ib_register_peer_memory_client`
is absent from the kernel) but **doesn't exist for 6.11 either**, and 6.11 works,
so GPUDirect peer memory was never in play. `ib_write_bw` host-to-host also
succeeds at 108 Gb/s on the broken kernel, because it runs on the *host*.

**How it happened:** `apt-get dist-upgrade` followed the `linux-nvidia-hwe-24.04`
metapackage from 6.11.0-1016 → 7.0.0-1019, and **removed the 6.11 NVIDIA modules**
as obsolete — so the first rollback boot came up with no GPU at all.

**Recovery / pin (both nodes):**

```bash
# restore the old kernel's NVIDIA modules (apt may claim "already newest"
# while /lib/modules/6.11.0-1016-nvidia has ZERO nvidia*.ko — use --reinstall)
sudo apt-get install --reinstall -y linux-modules-nvidia-580-open-6.11.0-1016-nvidia
find /lib/modules/6.11.0-1016-nvidia -name 'nvidia*.ko*' | wc -l    # expect 8

# make 6.11 the permanent default (IDs differ per node — read each node's own grub.cfg)
SUB=$(sudo grep -oE 'gnulinux-advanced-[a-f0-9-]+' /boot/grub/grub.cfg | head -1)
ID=$(sudo grep -oE 'gnulinux-6\.11\.0-1016-nvidia-advanced-[a-f0-9-]+' /boot/grub/grub.cfg | head -1)
sudo grub-set-default "$SUB>$ID"

# stop dist-upgrade pulling 7.0.0 back in
sudo apt-mark hold linux-nvidia-hwe-24.04 linux-image-nvidia-hwe-24.04 \
                   linux-modules-nvidia-580-open-nvidia-hwe-24.04
```

Use `grub-reboot` (one-shot, self-reverting) rather than `grub-set-default` while
still testing an unproven kernel.

### 2026-09-14: serving DeepSeek-V4-Flash (non-B12X) — the working config

Verified serving on 2026-09-14: correct answers, 4-way concurrency, 2k-token
prompts, ~1 s latency, `-tp2-` in `system_fingerprint`, `Worker_TP` busy on the
worker, zero RDMA errors.

| | |
|---|---|
| Model | `deepseek-ai/DeepSeek-V4-Flash` (not `-0731`) |
| Container | `vllm-node` (stock), **vLLM 0.29.1rc1** |
| Recipe | `deepseek-v4-flash-safetensors.yaml` (local variant, kept in this dir) |
| max_model_len | 131072 (via `MAX_MODEL_LEN` in the start script) |
| gpu_memory_utilization | **0.90** |
| Weights | 75.77 GiB/node · GPU KV cache 464,928 tokens |

Three fixes were needed beyond the kernel rollback:

1. **`vllm: error: unrecognized arguments: --reasoning-config`** — the stock
   container shipped vLLM 0.17.2rc1 (March), older than the recipe. Rebuild with
   the prebuilt wheel instead of compiling:
   ```bash
   cd ~/spark-vllm-docker
   ./build-and-copy.sh --use-wheels --force-vllm-download   # head image
   ./build-and-copy.sh --no-build --copy-to 192.168.100.11  # push to worker
   ```
   Wheels come from the upstream `prebuilt-vllm-current` release. **`--use-wheels`
   is incompatible with `--exp-b12x`** (no B12X wheels are published), so this
   rebuilds only the stock image; `vllm-node-b12x` is left alone.
   Verify both nodes match: `docker images --no-trunc --format '{{.ID}}' vllm-node:latest`.

2. **`RuntimeError: buffer_size (1059061760 B) exceeds device memory budget (...)`**
   — raised `gpu_memory_utilization` 0.8 → **0.90**. This is *not* a model-size or
   context-length problem (the model needs only 75.77 GiB of 128 GB, and lowering
   `max_model_len` 500000 → 131072 changed nothing). It is `instanttensor`'s weight
   **load buffer**, whose budget scales with `gpu_memory_utilization`.
   `--load-format safetensors` does **not** avoid it — this build still routes
   through `instanttensor.safe_open` and just shrinks `io_depth` (256 → 71 → 42)
   until it gives up.

3. **`max_model_len`** — the recipe's 500000 is fine for memory but the start
   script pins 131072 for headroom; override with `MAX_MODEL_LEN=...`.

Benign noise in this configuration, safe to ignore:
- `Failed to load plugin b12x_loader ... cannot import name 'file_source_tensor'`
  — the B12X plugin is baked into the image and expects an older vLLM API. It is
  skipped harmlessly here, but means **the B12X recipe now has a plugin/vLLM
  mismatch** if you switch back to it.
- `Failed to import the DeepSelect extension (vllm._deepselect_C)`
- `Unknown vLLM environment variable detected: VLLM_BASE_DIR`
- `torch.compile is turned on, but the model ... does not support it`

### Faster rebuilds: pull the prebuilt base image

`eugr/spark-vllm:latest` on Docker Hub is ~11.2 GB and rebuilt nightly
(`nightly-YYYYMMDD` tags), so `--setup` can pull it instead of building locally.
Note it is a **different image** from `eugr/spark-vllm-b12x` — the B12X recipes
need the b12x variant, built with `--exp-b12x`.

### "Only 5-6 GB free!" — unified memory makes `free` look alarming

The GB10 has **unified memory**: GPU allocations come out of the same 121 GiB
pool, so model weights and KV cache show up as *used* in `free -h`. A healthy
serving node looks like this:

```
              total  used  free  shared  buff/cache  available
Mem:          121Gi  116Gi 5.2Gi  2.4Gi     3.8Gi      5.2Gi
Swap:          15Gi     0B
```

That 116 GiB is mostly the model, exactly as configured:

| | |
|---|---|
| Weights | 75.77 GiB |
| KV cache | 23.82 GiB |
| = GPU total | ~99.6 GiB |
| + process RSS, page cache, OS | → ~116 GiB |

`gpu_memory_utilization: 0.90` *tells* vLLM to claim 90% of each node, so ~5-6 GiB
free is the intended headroom, not exhaustion. Two corroborating signals:
`VLLM::Worker_TP` shows only ~5 GiB **RSS** (the model is in GPU allocations, not
process memory), and **`Swap: 0B` used** means nothing is under pressure.

`nvidia-smi` reports `memory.used [N/A]` on this hardware for the same reason —
there is no separate VRAM to report. Use `free -g` plus the vLLM startup lines
(`Model loading took N GiB`, `GPU KV cache size: N tokens`) instead.

Judge health by behaviour, not by free memory: concurrent requests succeeding,
`vllm:kv_cache_usage_perc` from `/metrics`, and no swap usage. Lowering
`gpu_memory_utilization` to 0.85 would free ~6 GiB/node but shrinks the KV cache
and the concurrency multiplier — and 0.90 is what fixed the `buffer_size` failure.

### Watching the cluster live

No `nvtop` on either node (`sudo apt-get install -y nvtop` if you want it). A
serviceable live view, run from either node:

```bash
watch -n 2 'curl -s http://192.168.100.10:8000/metrics \
  | grep -E "kv_cache_usage_perc|num_requests_(running|waiting)\{|generation_tokens_total" \
  | sed "s/{[^}]*}//"; \
  nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,power.draw --format=csv,noheader; \
  free -g | awk "NR==2{print \"mem \"\$3\"/\"\$2\"GB\"}"'
```

Note the metrics endpoint only exists on the **head** (the API server); the
worker has no HTTP endpoint, so query `192.168.100.10:8000` from either node.

### `NCCL error: unhandled system error` after a Docker upgrade (memlock)

Symptom: vLLM dies during `init_device()` / `init_model_parallel_group` with

```
RuntimeError: NCCL error: unhandled system error (run with NCCL_DEBUG=INFO for details)
```

and with debug enabled the real error is:

```
NCCL WARN Call to ibv_reg_mr_iova2 failed with error Cannot allocate memory
```

**Cause: Docker's default `memlock` ulimit.** RDMA must *pin* (lock) the memory
the NIC DMAs into, and a 284B model pins tens of GB. Docker 28 effectively left
memlock unlimited; **Docker 29 caps it at 8 MB**, so `ibv_reg_mr` fails inside
the container while the host is fine. Hit on 2026-09-13 immediately after the
28.3.3 → 29.2.1 upgrade; the same config had served all morning.

Misleading signals — don't chase these:
- `ib_write_bw` between the nodes succeeds (108 Gb/s). It runs on the **host**,
  where memlock is ample for its small buffers; only containers are capped.
- NCCL debug shows the fabric found correctly (`Using network IB`, RoCE
  200 Gb/s, channels built). Transport selection is *not* the problem.
- `rdma link show` is ACTIVE, QSFP pings, TCP over QSFP works.

Fix — on **both** nodes:

```bash
sudo mkdir -p /etc/docker
echo '{"default-ulimits":{"memlock":{"Name":"memlock","Hard":-1,"Soft":-1}}}' \
  | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker      # this destroys all containers
```

Verify with `docker run --rm ubuntu:24.04 bash -c 'ulimit -l'` → `unlimited`.

**Order matters:** write `daemon.json` → restart Docker → *then* relaunch vLLM
(`sudo systemctl restart vllm-cluster`). Restarting Docker kills `vllm_node` on
both nodes, and vLLM (and Ray, on the Ray recipes) runs inside those containers,
so it must be relaunched afterwards or it comes back under the old limit.

### Getting NCCL debug output at all

`CONTAINER_NCCL_DEBUG=INFO` is documented by `launch-cluster.sh`, but
`run-recipe.sh` does **not** forward it — a recipe run produces zero `NCCL INFO`
lines. Call the launcher directly instead:

```bash
cd ~/spark-vllm-docker
./launch-cluster.sh -e NCCL_DEBUG=INFO -e NCCL_DEBUG_SUBSYS=INIT,NET,ENV \
    -t vllm-node-b12x -n 192.168.100.10,192.168.100.11 \
    exec vllm serve <model> --tensor-parallel-size 2 --max-model-len 65536
```

A small `--max-model-len` makes it fail fast at the NCCL stage instead of
spending minutes on KV-cache sizing.

**`exec` skips container creation if any node still has one**, printing
`Cluster containers are already running. Skipping launch.` and then
`Error response from daemon: No such container: vllm_node` when the other node
has none. Env flags passed with `-e` are then silently not applied. Always run
`./cleanup-containers.sh` (and confirm `docker ps -aq` is empty on *both* nodes)
before a debug launch.

### `--download-only` STOPS the running cluster

`run-recipe.sh <recipe> --download-only` is **not** side-effect free: the runner
tears the containers down as part of its lifecycle, so a download kicked off
while serving will stop the service (`Stopping cluster... / Stopping worker
node...` in the journal) and leave `vllm-cluster` inactive. Verified 2026-09-13.
Plan downloads as downtime, or expect to `systemctl start vllm-cluster` after.

### `/health` returns 200 while inference hangs

When the worker's container dies but the head's survives, the API server keeps
answering `/health` with 200 while the engine blocks waiting for the missing
rank. The tell in the journal is:

```
shm_broadcast.py: No available shared memory broadcast block found in 60 seconds
```

**Always smoke-test with a real completion, not `/health`:**

```bash
curl -s -m 60 http://100.87.122.108:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"<served name>","messages":[{"role":"user","content":"say OK"}],"max_tokens":10}'
```

### Worker sshd stops completing handshakes (port open, no banner)

Symptom: `ping` fine (<1 ms), `ip neigh` REACHABLE, TCP connect to 22 succeeds,
but every ssh dies with `Connection timed out during banner exchange`. That is
sshd unable to fork sessions — not a down or booting machine.

Biggest self-inflicted cause: **piling up concurrent `ssh` probes to the worker**
(monitoring one-liners in a loop) exhausts `MaxStartups`. Check and clear from
the head with `pgrep -af 'ssh.*192.168.100.11'` then `pkill -f`. Note `pkill`
run *through* such a connection kills your own session (exit 255).

The worker also idles near 88% memory with the model resident, so genuine
resource exhaustion is plausible. If clearing probes doesn't restore ssh, a
reboot does — but the node is then unmanageable remotely until it comes back.

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

### spark-771e dies silently — diagnosing power loss vs. a software crash

Investigated 2026-09-13 after four worker deaths in six days (Sep 7, 8, 10, 12,
13) while spark-f5ea sat at 42 days uptime on the same rack.

**The decisive evidence is the SSD's own counter:**

```bash
sudo nvme smart-log /dev/nvme0n1 | grep -E 'unsafe_shutdowns|power_cycles|critical_warning|media_errors|percentage_used'
```

It read `unsafe_shutdowns: 18` of `power_cycles: 48` — the drive firmware
counted 18 losses of power without warning, ~38% of all boots. Everything else
was clean: `critical_warning 0`, `media_errors 0`, `percentage_used 0%`.

Corroborating signs that it is **power, not software**:
- `journalctl --list-boots` shows prior boots ending mid-sentence with **no**
  shutdown record — grep `systemd-shutdown|Powering off|Reached target Shutdown`
  across `-b -1/-2/-3` and get zero hits.
- No kernel panic, no OOM kill, no thermal event, no Xid/NVRM GPU fault.
- Deaths landed during idle `sysstat-collect` / `debian-sa1` cron runs, **not**
  under inference load — which rules out "the model draws too much power".
- The head node, same rack, never flinched.

Also note the worker's **RTC resets to Jul 2025 on every boot** (likely a dead
CMOS battery), so `docker ps` uptimes and log correlation on that node lie —
`Up 17 hours` on a 10-minute-old boot. Treat worker timestamps with suspicion.

Software updates do **not** address this: both nodes were brought to identical
kernel 7.0.0-1019-nvidia / Docker 29.2.1 / NVIDIA 580.x on 2026-09-13 and the
fault is independent of that. With the node on its own outlet behind a UPS, the
remaining suspects are the PSU or the unit itself → warranty.

`GRUB_TIMEOUT=10` + `GRUB_TIMEOUT_STYLE=menu` were set on both nodes so a failed
kernel can be escaped from a console; the generated menu also exposes a **UEFI
Firmware Settings** entry, which is the only way into AMI setup on these
headless boxes (needed to check auto-power-on-after-AC-loss, since there is no
`/proc/acpi/wakeup` and no BMC/ipmi device).

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
| `max_model_len` (`auto` resolved) | **716,800 – 874,496** (varies, see below) |
| Model load | 81.34 GiB/node, ~30-40 s (weights alone) |
| GPU KV cache | 786,423 – 959,451 tokens (1.10x concurrency at max len) |
| Generation throughput | **~64 tok/s** (193 tok, single stream, warm) |
| Startup wall time | ~3.5-4.5 min (start → `Application startup complete`) |

**`max_model_len: auto` resolves differently on each start** — it is sized from
KV memory free at that moment. Observed 874,496 right after a cache drop and
716,800 on a later start. This is normal. Keep OpenCode's limits under the
*lower* end (currently 262144 + 32000) so a restart never invalidates them; check
`curl .../v1/models` if you need the current value.

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
| `QuantTrio/MiniMax-M2.5-AWQ` | ✅ Working | **Ray**, stock `vllm-node`, no experimental flags. Known-good fallback; weights cached on both nodes |
| `deepseek-ai/DeepSeek-V4-Flash-0731` | ✅ Working | **NCCL, not Ray.** NVIDIA's experimental B12X stack (`vllm-node-b12x`, `B12X_MLA_SPARSE`, b12x MoE/linear, dspark spec decoding, 16 B12X env vars, instanttensor mod). First serve 2026-09-08, ~4 min cold start, 785K context but only 1.10x concurrency. Its in-image b12x plugin is now mismatched against newer vLLM |
| `deepseek-ai/DeepSeek-V4-Flash` | ✅ **Working — current default (2026-09-14)** | Stock `vllm-node` on vLLM 0.29.1rc1, no MoE backend flags. 131072 ctx, 464,928-token KV cache, **3.55x** concurrency, 75.77 GiB/node. Needs `gpu_memory_utilization: 0.90` (see the working-config section). Despite `--distributed-executor-backend ray` in the recipe, this vLLM runs MultiprocExecutor/NCCL |
| `unsloth/MiniMax-M3-GGUF` (UD-IQ3_XXS) | ❌ Blocked on vLLM | no minimax-m3 GGUF support anywhere in vLLM (in-tree or plugin) as of 2026-07; file staged on both nodes; llama.cpp is the viable route |
| `zai-org/GLM-4.5-Air` | ❌ Not working | 99.6GB, never got working on dual Spark |

## Model Selection Resources

- **LiveBench** (open-weight, high unseen bias filter): https://livebench.ai/#/?openweight=true&highunseenbias=true
  - Use this to compare open-weight models on benchmarks with low data contamination risk
  - Filter by context length and task type to find candidates for this cluster
