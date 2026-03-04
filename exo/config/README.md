# Exo Cluster Configuration

This directory contains configuration for your exo cluster setup.

## Cluster Details

| Machine | Role | LAN IP | Tailscale IP | OS |
|---------|------|--------|-------------|-----|
| Mac Studio (Miriah's) | Main + Compute | 192.168.1.242 | 100.71.226.113 | macOS (EXO.app) |
| Spark f5ea | Compute Node | 192.168.1.9 | 100.87.122.109 | Ubuntu Linux (aarch64, NVIDIA) |
| Spark 771e | Compute Node | 192.168.1.84 | 100.112.230.20 | Ubuntu Linux (aarch64, NVIDIA) |

- **Namespace**: `soypete_tech`
- **Network**: Hardline connected via Ubiquiti switch and Dream Machine
- **Peer Discovery**: mDNS (requires same LAN broadcast domain)

## Directory Structure

```
exo/
├── config/     # Configuration files
├── scripts/    # Management scripts
└── logs/       # Log files
```

## Connecting to the Cluster Remotely (via Tailscale)

You can access any node's exo API from any device on your Tailnet. Exo binds
to `0.0.0.0:52415`, so it's accessible on all interfaces including Tailscale.

**From your laptop (or any Tailscale device):**

```bash
# Query the Mac Studio
curl -s http://100.71.226.113:52415/state | jq '.topology'

# Query Spark f5ea
curl -s http://100.87.122.109:52415/state | jq '.topology'

# Query Spark 771e
curl -s http://100.112.230.20:52415/state | jq '.topology'

# Use the OpenAI-compatible API via Tailscale
curl http://100.71.226.113:52415/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mlx-community/Llama-3.1-8B-Instruct-4bit",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

**Run Claude Code against the cluster from your laptop:**

```bash
ANTHROPIC_AUTH_TOKEN="" \
ANTHROPIC_BASE_URL="http://100.71.226.113:52415/v1" \
claude --model mlx-community/Llama-3.1-8B-Instruct-4bit
```

**Important**: Tailscale uses /32 addresses (no broadcast domain), so mDNS
peer discovery does NOT work over Tailscale. The cluster nodes must be on the
same LAN for mDNS discovery. Your laptop connects to the cluster's API only —
it does not join the cluster as a compute node.

## Peer Discovery (mDNS)

Exo uses libp2p mDNS for automatic peer discovery. All cluster nodes must be
on the **same LAN broadcast domain** for this to work.

**Requirements:**
- All nodes on the same VLAN/subnet (192.168.1.x/24)
- Same `EXO_LIBP2P_NAMESPACE` on all nodes (currently: `soypete_tech`)
- Ubiquiti Gateway mDNS Proxy must allow libp2p mDNS traffic:
  - Set Service Scope to **"All"**, OR
  - Set Gateway mDNS Proxy to **"Auto"** or **"Off"**

**Troubleshooting discovery:**
```bash
# Check namespace matches on each node
echo $EXO_LIBP2P_NAMESPACE
# Should be: soypete_tech

# From a Spark, verify mDNS can see other devices
avahi-browse -a -t | head -20

# Check topology (should show multiple nodes)
curl -s http://localhost:52415/state | jq '.topology'
```

## Setup Instructions

### Mac Studio (EXO Desktop App)

The Mac Studio runs the [EXO desktop app](https://github.com/exo-explore/exo)
(`/Applications/EXO.app`). Set the namespace in the app settings to `soypete_tech`.

### Spark Nodes (Linux, from source)

**Prerequisites:** `uv`, `node`, `npm`

```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc

# Install node/npm (if not present)
sudo apt update && sudo apt install -y nodejs npm

# Clone exo
git clone https://github.com/exo-explore/exo ~/code/exo

# Build dashboard
cd ~/code/exo/dashboard && npm install && npm run build && cd ..

# Set namespace
echo 'export EXO_LIBP2P_NAMESPACE="soypete_tech"' >> ~/.bashrc
source ~/.bashrc

# Start exo
cd ~/code/exo
nohup uv run exo > ~/exo.log 2>&1 &
```

**SSH access to Spark 771e:** This node is coupled to Spark f5ea and can only
reach the outside network (internet, Tailscale) through Spark f5ea. You must
hop through Spark f5ea to reach it:

```bash
ssh soypete@100.87.122.109   # Mac -> Spark f5ea
ssh soypete@192.168.1.84     # Spark f5ea -> Spark 771e
```

Because of this coupling, Spark 771e:
- May not have Tailscale connectivity unless explicitly configured
- Relies on Spark f5ea for internet access (package installs, model downloads)
- Is reachable on LAN (192.168.1.84) from devices on the same subnet

### Systemd Service (Linux auto-start)

To run exo as a service on the Spark nodes:

```bash
sudo tee /etc/systemd/system/exo.service << 'EOF'
[Unit]
Description=Exo Cluster Node
After=network.target

[Service]
User=soypete
WorkingDirectory=/home/soypete/code/exo
Environment=EXO_LIBP2P_NAMESPACE=soypete_tech
Environment=PATH=/home/soypete/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/soypete/.local/bin/uv run exo
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable --now exo
```

**Manage the service:**
```bash
sudo systemctl status exo        # Check status
sudo systemctl restart exo       # Restart
sudo journalctl -u exo -f        # View logs
```

## API Endpoints

Any node can serve the API. Use whichever is convenient:

- **Local**: `http://localhost:52415`
- **Mac Studio (Tailscale)**: `http://100.71.226.113:52415`
- **Spark f5ea (Tailscale)**: `http://100.87.122.109:52415`
- **Spark 771e (Tailscale)**: `http://100.112.230.20:52415`

Endpoints:
- **Dashboard**: `http://<ip>:52415`
- **Cluster state**: `http://<ip>:52415/state`
- **Models list**: `http://<ip>:52415/models`
- **OpenAI-compatible**: `http://<ip>:52415/v1/chat/completions`

## Models

**IMPORTANT**: Exo on Apple Silicon requires **MLX-format models** from the
`mlx-community` organization on Hugging Face.

See **MODELS.md** in this directory for complete documentation.

**Recommended:**
- `mlx-community/Llama-3.1-8B-Instruct-4bit` (general chat)
- `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit` (code generation)
- `mlx-community/Llama-3.2-3B-Instruct-4bit` (faster, smaller)

```bash
# List models
curl -s http://localhost:52415/models | jq '.'
```

Browse all MLX models: https://huggingface.co/mlx-community

## Running Claude Code with Exo

Use the `exo-claude` function to run Claude Code with a specific model:

```bash
# Show usage and available models
exo-claude

# Run with a specific MLX model
exo-claude mlx-community/Llama-3.1-8B-Instruct-4bit
exo-claude mlx-community/Qwen2.5-Coder-7B-Instruct-4bit
```

The function automatically sets the correct environment variables:
- `ANTHROPIC_AUTH_TOKEN=""` (empty for local cluster)
- `ANTHROPIC_BASE_URL="http://100.87.122.109:52415/v1"`
- `--model <your-specified-model>`

**From a remote laptop (via Tailscale):**

```bash
ANTHROPIC_AUTH_TOKEN="" \
ANTHROPIC_BASE_URL="http://100.71.226.113:52415/v1" \
claude --model mlx-community/Llama-3.1-8B-Instruct-4bit
```

Models are automatically downloaded from Hugging Face on first use.

## Benchmarking

See **BENCHMARKING.md** for complete guide.

```bash
# SSH to a Spark
ssh soypete@100.87.122.109
cd ~/code/exo
uv run bench/exo_bench.py \
  --model mlx-community/Llama-3.1-8B-Instruct-4bit \
  --pp 128,256,512 \
  --tg 128,256 \
  --max-nodes 2 \
  --repeat 3
```
