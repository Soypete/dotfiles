# Running OpenCode on Your Homelab ARM Cluster with Exo

A few people asked in the comments on my recent podcast video how I'm running an AI coding assistant on my homelab without paying for API access. This post is the full answer — actual commands, real gotchas, and everything you need to replicate it.

The short version: I'm using [exo](https://github.com/exo-explore/exo) to pool inference across two ARM nodes, then pointing [OpenCode](https://opencode.ai) at the cluster's OpenAI-compatible endpoint. It took some wrestling to get right, but once it clicked, it works beautifully.

---

## The Hardware

Here is what I am running:

| Machine | Role | OS |
|---------|------|----|
| Mac Studio | Client (runs OpenCode) | macOS |
| Spark 1 (aarch64, NVIDIA) | Compute Node | Ubuntu Linux |
| Spark 2 (aarch64, NVIDIA) | Compute Node | Ubuntu Linux |

All three are hardwired to a Ubiquiti switch. Tailscale handles remote access. The two Spark nodes auto-discover each other via mDNS on the LAN — Tailscale cannot do mDNS since it uses /32 addresses with no broadcast domain, so the nodes must be on the same physical subnet. (More on that in the gotchas section, because it will bite you if you skip it.)

---

## Why Exo?

The problem with running large models locally is that a single machine rarely has enough VRAM. Exo solves this by letting you pool compute across multiple machines so your cluster acts as a single inference backend. It exposes an OpenAI-compatible API on port `52415`, which means anything that speaks OpenAI format — including OpenCode — just works with it out of the box.

On Apple Silicon, exo uses MLX-format models from [mlx-community](https://huggingface.co/mlx-community) on Hugging Face. On Linux with NVIDIA hardware, it uses CUDA. My Spark nodes are ARM with NVIDIA GPUs, so they run the CUDA path.

The result: a 70B parameter model, quantized to 4-bit, split across two nodes, running entirely on hardware I already own.

---

## Step 1: Install Exo on Each Linux Node

SSH into each Spark node and run the following. You'll do this on both nodes.

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

## Step 2: Set the Cluster Namespace

This step is easy to overlook and painful to debug. Every node must use the **same namespace** or they will not discover each other. Pick a name, use it everywhere, and do not change it later.

```bash
echo 'export EXO_LIBP2P_NAMESPACE="my_cluster"' >> ~/.bashrc
source ~/.bashrc
```

If your nodes are not seeing each other, a mismatched namespace is almost always the cause. Verify it on every node with:

```bash
echo $EXO_LIBP2P_NAMESPACE  # must match on every node
```

## Step 3: Run Exo as a Systemd Service

Running it manually with `nohup` works for a quick test, but it does not survive reboots. Set up a proper systemd service from the start and save yourself the trouble later.

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
ExecStart=/home/YOUR_USER/.local/bin/uv run exo
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable exo
sudo systemctl start exo
```

**One gotcha worth calling out now:** you must set `Environment=HOME=/home/YOUR_USER`. Without it, systemd's minimal environment breaks pyo3 (the Rust/Python bridge exo uses) and the service crashes immediately with:

```
assertion `left != right` failed: The Python interpreter is not initialized
```

If that error is not enough to explain what went wrong, you are in for a confusing afternoon. Set `HOME` explicitly and move on.

If you are still seeing crashes, switch to a login shell in the service definition:

```ini
ExecStart=/bin/bash -lc 'cd /home/YOUR_USER/code/exo && uv run exo'
```

The `-l` flag sources your full login environment, which usually resolves any remaining Python path issues.

Check that everything is running:

```bash
sudo systemctl status exo
sudo journalctl -u exo -f
```

## Step 4: Verify the Cluster

Once both nodes are running, confirm they have found each other. From any machine on your network or Tailnet:

```bash
curl -s http://<SPARK_IP>:52415/state | jq '.topology'
```

You should see all your nodes listed. Then check which models are available:

```bash
curl -s http://<SPARK_IP>:52415/v1/models | jq '.data[].id'
```

Models auto-download from Hugging Face on first use, but I recommend triggering downloads manually before your first OpenCode session (covered in Step 7). Nothing kills momentum like waiting 40 minutes for a 70B model to download mid-conversation.

## Step 5: Set Up Tailscale Access

Exo binds to `0.0.0.0:52415`, which means it is reachable on all interfaces, including your Tailscale interface. From any device on your Tailnet:

```bash
curl -s http://<TAILSCALE_IP>:52415/state | jq '.topology'
```

Add these to your `~/.zshrc` or `~/.bashrc` on your client machine (the Mac Studio, in my case):

```bash
SPARK_NODE="<YOUR_SPARK_TAILSCALE_IP>"
export EXO_API_URL="http://${SPARK_NODE}:52415"
export EXO_API_BASE_URL="${EXO_API_URL}/v1"
```

Using an environment variable for the base URL is intentional — it lets you swap which node you point at without touching the OpenCode config file.

## Step 6: Configure OpenCode

OpenCode stores its config at `~/.config/opencode/opencode.json` (or `$XDG_CONFIG_HOME/opencode/opencode.json` if you have that set). Create it with the exo cluster as a custom OpenAI-compatible provider:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": true,
  "model": "exo/mlx-community/Llama-3.3-70B-Instruct-4bit",
  "provider": {
    "exo": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Exo Cluster",
      "options": {
        "baseURL": "{env:EXO_API_BASE_URL}",
        "apiKey": "fake"
      },
      "models": {
        "mlx-community/Llama-3.3-70B-Instruct-4bit": {
          "name": "Llama 3.3 70B 4bit",
          "limit": { "context": 128000, "output": 8192 }
        },
        "mlx-community/Qwen3-30B-A3B-4bit": {
          "name": "Qwen3 30B 4bit",
          "limit": { "context": 32000, "output": 8192 }
        },
        "mlx-community/GLM-4.7-8bit-gs32": {
          "name": "GLM-4.7 8bit",
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
  },
  "formatter": {
    "goimports": {
      "command": ["goimports", "-w", "$FILE"],
      "extensions": [".go"]
    }
  }
}
```

A few things in here that are not obvious:

- `"npm": "@ai-sdk/openai-compatible"` tells OpenCode to use the OpenAI-compatible provider adapter. This is the key that makes it work with exo.
- `"apiKey": "fake"` — exo does not require authentication, but the field is required by the provider adapter. Any non-empty string works.
- `{env:EXO_API_BASE_URL}` pulls the URL from your shell environment at runtime, so you can change nodes without editing this file.
- You must define models explicitly. OpenCode does not auto-discover them from the exo API, unlike some other tools.
- The `extensions` array on each LSP server entry is **required**. OpenCode will refuse to start and throw a config validation error if it is missing.

## Step 7: Download a Model and Run

Before starting OpenCode, trigger the model download manually on your Spark node. This avoids a long silent wait (or a timeout) the first time OpenCode tries to use it.

```bash
ssh YOUR_USER@<SPARK_IP>
cd ~/code/exo
uv run exo download mlx-community/Llama-3.3-70B-Instruct-4bit
```

A 70B 4-bit model is roughly 40GB, so this takes a while. If you want to test the full pipeline first before committing to that download, `Llama-3.2-3B-Instruct-4bit` is about 2GB and will tell you quickly whether everything is wired up correctly.

Once the download finishes, back on your client machine:

```bash
source ~/.zshrc  # pick up EXO_API_BASE_URL
opencode
```

OpenCode connects to the cluster and uses whatever model you set as the default in your config.

---

## Real Gotchas — Things That Will Bite You

I could have buried these at the end with a sentence like "and that is all there is to it," but that would be dishonest. Here is what actually cost me time.

### 1. Tailscale IPs Do Not Work for Node Discovery

This one burned me for longer than I want to admit. Exo uses libp2p mDNS for auto-discovery between nodes. mDNS requires a broadcast domain — Tailscale uses point-to-point /32 addresses and does not have one. So **cluster nodes cannot discover each other over Tailscale**.

Your compute nodes must be on the same physical LAN subnet (e.g., `192.168.1.x`). Tailscale is only useful for *clients* connecting to the cluster API from outside the LAN — not for the nodes finding each other.

One more wrinkle: if you are using a Ubiquiti Dream Machine or similar router, mDNS proxying can block libp2p traffic even on the same subnet. Fix it by setting the Gateway mDNS Proxy Service Scope to **"All"** in your Ubiquiti settings.

### 2. The Namespace Must Match Exactly on Every Node

Exo uses a namespace to isolate clusters from each other. Nodes with different namespaces simply ignore each other — no error, no warning, they just do not connect. This is by design, but it makes debugging confusing because silence is not a helpful error message.

Set the namespace in `.bashrc` on every Linux node:

```bash
echo 'export EXO_LIBP2P_NAMESPACE="my_cluster"' >> ~/.bashrc
source ~/.bashrc
```

And make sure your systemd service also has it — this is the part people miss:

```ini
Environment=EXO_LIBP2P_NAMESPACE=my_cluster
```

If you set it in `.bashrc` but not in the service file, the service runs with an empty namespace and will not join the cluster. Your terminal sessions look fine; the service is silently isolated.

### 3. Spark 2 Has No Direct External Access

In my setup, Spark 2 is physically coupled to Spark 1 — it routes all internet traffic through Spark 1 and does not have its own Tailscale connectivity. That means:

- You cannot SSH directly to Spark 2 from outside the LAN. You hop through Spark 1 first.
- Model downloads on Spark 2 go through Spark 1's internet connection.
- Spark 2 is LAN-reachable (`192.168.1.x`) but not Tailscale-reachable.

```bash
# Mac → Spark 1
ssh user@<SPARK_1_TAILSCALE_IP>

# Spark 1 → Spark 2 (LAN only)
ssh user@192.168.1.84
```

If your setup is similar, keep this in mind for model downloads. If Spark 2 cannot reach Hugging Face directly, download on Spark 1 and let the cluster share it.

### 4. Systemd Crashes Without HOME Set

Systemd runs services with a minimal environment — no `HOME`, no shell config, no PATH beyond the defaults. Exo uses pyo3 (a Rust/Python bridge) which needs a working Python environment that depends on `HOME` being set. Without it, you get this:

```
assertion `left != right` failed: The Python interpreter is not initialized
```

Fix: add `Environment=HOME=/home/YOUR_USER` to the `[Service]` section. If you are still seeing failures, switch to a login shell:

```ini
ExecStart=/bin/bash -lc 'cd /home/YOUR_USER/code/exo && uv run exo'
```

The `-l` flag sources your full login environment and usually resolves whatever the minimal environment was missing.

### 5. Download Models Before Your First Session

Exo downloads models from Hugging Face on first use. If you launch OpenCode immediately after pointing it at a new model, it will either time out or return "No instance found for model." Pre-download to avoid the frustration:

```bash
ssh user@<SPARK_IP>
cd ~/code/exo
uv run exo download mlx-community/Llama-3.3-70B-Instruct-4bit
```

For reference: Llama 3.3 70B 4-bit is roughly 40GB. Plan accordingly.

### 6. OpenCode Requires Explicit Model Definitions

Unlike Claude Code, which queries the API for available models, OpenCode requires you to list every model explicitly in your config along with its context window limits. If a model is not in the `models` object, it will not appear in the model picker.

Also: the `extensions` array on LSP server entries is required. OpenCode will refuse to start if it is missing, and the validation error message is clear enough, but it is easy to copy a config snippet that omits it.

### 7. OpenCode and Claude Code Use Different API Formats

This is worth knowing before you go down the wrong path. Claude Code speaks Anthropic's API format (`/v1/messages`). OpenCode speaks OpenAI format (`/v1/chat/completions`). Exo only serves OpenAI format. So:

- **OpenCode to exo**: works directly
- **Claude Code to exo**: needs a translation proxy

If you specifically want Claude Code backed by your cluster, run LiteLLM in front of exo to translate the formats:

```bash
pip install litellm
litellm --model openai/mlx-community/Llama-3.3-70B-Instruct-4bit \
        --api_base http://<SPARK_IP>:52415/v1 \
        --port 4000
```

Then:

```bash
ANTHROPIC_BASE_URL="http://localhost:4000" \
ANTHROPIC_AUTH_TOKEN="fake" \
claude --model mlx-community/Llama-3.3-70B-Instruct-4bit
```

---

## The Result

Once this is all running, you have a fully local AI coding assistant backed by your own cluster — accessible from anywhere on your Tailnet, no API keys, no usage limits, no data leaving your network.

The performance is not going to match a commercial API for raw speed, but it is fast enough to be genuinely useful, and the economics are different: the hardware cost is a one-time expense and the marginal cost of each query is zero.

The full dotfiles config, including all the scripts referenced here, is on GitHub: [Soypete/dotfiles](https://github.com/Soypete/dotfiles). If something in this post is unclear or out of date, that is the best place to open an issue.
