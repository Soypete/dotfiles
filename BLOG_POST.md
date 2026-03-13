# I Tried to Run a Distributed AI Cluster on DGX Sparks. Here Is What Actually Happened.

The premise was great: pool my Mac Studio and two NVIDIA DGX Spark nodes into a single inference cluster using [exo](https://github.com/exo-explore/exo), point [OpenCode](https://opencode.ai) at it, and have a fully local AI coding assistant running on hardware I already own. No API bills. No data leaving my network.

Some of it worked. Some of it was marketing I believed too early. Here is the honest account.

---

## The Hardware

| Machine | Role | OS |
|---------|------|-----|
| Mac Studio (M3 Ultra) | Client + Compute | macOS (EXO.app) |
| DGX Spark f5ea (aarch64, NVIDIA) | Intended Compute Node | Ubuntu Linux |
| DGX Spark 771e (aarch64, NVIDIA) | Intended Compute Node | Ubuntu Linux |

All three are hardwired to a Ubiquiti switch. Tailscale handles remote access.

The goal was to run a 70B model split across all three machines. EXO Labs published an article describing exactly this kind of disaggregated prefill/decode setup — prefill (compute-bound) on the NVIDIA nodes, decode (memory-bound) on the Mac Studio. It sounded like it was already shipping.

It is not. Not in the released version. More on that in a minute.

---

## Setting Up Exo — The Parts That Do Work

Even though the DGX Spark story fell apart, getting the cluster running on the Mac Studio side was genuinely useful and worth documenting. Here is what the working setup looks like.

### Step 1: Install Exo on Each Linux Node

SSH into each Spark and run:

```bash
# Install uv (Python package runner)
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc

# Install node/npm for the dashboard
sudo apt update && sudo apt install -y nodejs npm

# Clone exo
git clone https://github.com/exo-explore/exo ~/code/exo

# Build the dashboard
cd ~/code/exo/dashboard && npm install && npm run build && cd ..
```

### Step 2: Set the Cluster Namespace

Every node must use the **same namespace** or they will silently ignore each other. No error. No warning. They just do not connect.

```bash
echo 'export EXO_LIBP2P_NAMESPACE="my_cluster"' >> ~/.bashrc
source ~/.bashrc
```

Verify it matches on every node:

```bash
echo $EXO_LIBP2P_NAMESPACE
```

### Step 3: Run Exo as a Systemd Service

```bash
sudo tee /etc/systemd/system/exo.service << 'EOF'
[Unit]
Description=Exo Cluster Node
After=network.target tailscaled.service

[Service]
User=YOUR_USER
WorkingDirectory=/home/YOUR_USER/code/exo
Environment=HOME=/home/YOUR_USER
Environment=EXO_LIBP2P_NAMESPACE=my_cluster
Environment=PATH=/home/YOUR_USER/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/bin/bash -lc 'cd /home/YOUR_USER/code/exo && uv run exo'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable exo
sudo systemctl start exo
```

**Critical:** you must set `Environment=HOME=/home/YOUR_USER`. Without it, systemd's minimal environment breaks pyo3 (the Rust/Python bridge exo uses) and the service crashes immediately with:

```
assertion `left != right` failed: The Python interpreter is not initialized
```

If you still see crashes, switch to a login shell:

```ini
ExecStart=/bin/bash -lc 'cd /home/YOUR_USER/code/exo && uv run exo'
```

The `-l` flag sources your full login environment and resolves whatever the minimal systemd environment was missing.

### Step 4: Set the Namespace in the Service File Too

This is the part people miss. If you set `EXO_LIBP2P_NAMESPACE` in `.bashrc` but not in the systemd service file, the service runs with an empty namespace and will not join the cluster. Your terminal sessions look fine. The service is silently isolated.

```ini
Environment=EXO_LIBP2P_NAMESPACE=my_cluster
```

### Step 5: Tailscale IPs Do Not Work for Node Discovery

Exo uses libp2p mDNS for peer discovery. mDNS requires a broadcast domain. Tailscale uses point-to-point /32 addresses and does not have one. Your compute nodes must be on the same physical LAN subnet.

Tailscale is useful for *clients* connecting to the cluster API from outside the LAN. It is not useful for the nodes finding each other.

One more wrinkle: if you are using a Ubiquiti Dream Machine, mDNS proxying can block libp2p traffic even on the same subnet. Fix it by setting the Gateway mDNS Proxy Service Scope to **"All"** in your Ubiquiti settings.

### Step 6: Version Mismatch Will Crash Exo

If your Mac Studio is running the EXO desktop app and your Spark nodes are running exo from source, they must be on the **same version**. A mismatch produces pydantic validation errors in the logs:

```
ValidationError: NodeDownloadProgress
  Extra inputs are not permitted
  Field required [type=missing]
```

The service crashes and restarts in a loop. Fix it by checking out the exact version tag that matches the EXO desktop app on your Mac:

```bash
ssh user@<SPARK_IP>
cd ~/code/exo
git fetch --tags
git tag | sort -V | tail -20

# Check out the matching version
git checkout v0.x.x

# Rebuild the dashboard
cd dashboard && npm install && npm run build && cd ..

sudo systemctl restart exo
```

Find the EXO.app version under **About EXO** on the Mac Studio.

### Step 7: Verify the Cluster

```bash
curl -s http://<SPARK_IP>:52415/state | jq '.topology'
curl -s http://<SPARK_IP>:52415/v1/models | jq '.data[].id'
```

---

## Where It Falls Apart: No CUDA Engine

Here is where the dream hits the wall.

After all of the above — namespace alignment, systemd fixes, version pinning, mDNS configuration — I finally had the cluster running and tried to load a model on the DGX Sparks. The error:

```
RuntimeError: QMM NYI
```

QMM is quantized matrix multiply. NYI means "not yet implemented."

I dug into the exo source to understand why. The inference engines directory:

```
~/code/exo/src/exo/worker/engines/
├── image/
├── mlx/
└── __init__.py
```

There is no CUDA engine. In the current released version of exo (v1.0.68 at time of writing), the only inference backend is MLX.

[MLX](https://github.com/ml-explore/mlx) is Apple's array framework for machine learning. It does have a Linux/CUDA backend you can install:

```bash
pip install mlx[cuda]
```

But the quantized operations that `mlx-community` 4-bit models depend on — the QMM ops — are not implemented in the CUDA path. So even if you install the CUDA backend, loading a quantized model on NVIDIA hardware fails with that same error.

**The `mlx-community` models on Hugging Face are Apple Silicon only.** Exo's released version only has an MLX inference backend. NVIDIA hardware cannot currently participate in inference.

The EXO Labs article about DGX Spark + Mac Studio disaggregated prefill/decode is describing a future or internal capability. It is not in the public release. I believe it too early.

---

## What Does Work: Mac Studio + OpenCode

The cluster running on the Mac Studio alone works well. Exo handles the OpenAI-compatible API on port `52415`, and OpenCode connects to it with a custom provider config.

Set in `~/.zshrc`:

```bash
SPARK_NODE="<YOUR_SPARK_TAILSCALE_IP>"
export EXO_API_URL="http://${SPARK_NODE}:52415"
export EXO_API_BASE_URL="${EXO_API_URL}/v1"
```

OpenCode config at `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": true,
  "model": "exo/mlx-community/GLM-4.7-Flash-8bit",
  "provider": {
    "exo": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Exo Cluster",
      "options": {
        "baseURL": "{env:EXO_API_BASE_URL}",
        "apiKey": "fake"
      },
      "models": {
        "mlx-community/GLM-4.7-8bit-gs32": {
          "name": "GLM-4.7 8bit (largest)",
          "limit": { "context": 128000, "output": 8192 }
        },
        "mlx-community/GLM-4.7-Flash-8bit": {
          "name": "GLM-4.7 Flash 8bit",
          "limit": { "context": 128000, "output": 8192 }
        },
        "mlx-community/Llama-3.3-70B-Instruct-4bit": {
          "name": "Llama 3.3 70B 4bit",
          "limit": { "context": 128000, "output": 8192 }
        }
      }
    }
  },
  "lsp": {
    "go": {
      "command": ["gopls"],
      "extensions": [".go"]
    },
    "typescript": {
      "command": ["typescript-language-server", "--stdio"],
      "extensions": [".ts", ".tsx", ".js", ".jsx"]
    }
  }
}
```

A few things worth calling out:

- `"npm": "@ai-sdk/openai-compatible"` is what makes the custom provider work. Without it, OpenCode does not know how to speak to exo.
- `"apiKey": "fake"` — exo requires no authentication but the field cannot be empty.
- `{env:EXO_API_BASE_URL}` pulls from your shell environment at runtime.
- You must define models explicitly. OpenCode does not auto-discover them.
- The `extensions` array on each LSP entry is required. OpenCode will refuse to start without it.
- Pre-download models before your first session. Exo pulls from Hugging Face on first use. A 70B 4-bit model is ~40GB. Nothing kills momentum like a 40-minute download mid-conversation.

```bash
ssh user@<SPARK_IP>
cd ~/code/exo
uv run exo download mlx-community/Llama-3.3-70B-Instruct-4bit
```

---

## The Conclusion

The Mac Studio setup works. OpenCode talks to exo, exo runs MLX models, and I have a local AI coding assistant with no API keys and no usage limits. That part of the goal is achieved.

The DGX Spark nodes are currently decorative as far as exo inference is concerned. They run the service, they appear in the cluster topology, but they cannot execute any inference because there is no CUDA engine in the released version.

When CUDA support lands in exo, this setup becomes genuinely powerful. The EXO Labs team is clearly building toward disaggregated prefill/decode across heterogeneous hardware — the architecture makes sense and the article they published describes a real thing. It is just not released yet.

In the meantime, I will expand the cluster the right way: used Mac Minis. When they hit $100 a piece, I am building a rack. Until then, the Mac Studio carries the load.

The full dotfiles config for this setup is on GitHub: [Soypete/dotfiles](https://github.com/Soypete/dotfiles).
