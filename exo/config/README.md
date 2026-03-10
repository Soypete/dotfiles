# Exo Cluster Configuration

## Cluster Details

| Machine | Role | LAN IP | Tailscale IP | OS |
|---------|------|--------|-------------|-----|
| Mac Studio (Miriah's) | Main + Compute | 192.168.1.242 | 100.71.226.113 | macOS (EXO.app) |
| Spark f5ea | Compute Node | 192.168.1.9 | 100.87.122.109 | Ubuntu Linux (aarch64, NVIDIA) |
| Spark 771e | Compute Node | 192.168.1.84 | 100.112.230.20 | Ubuntu Linux (aarch64, NVIDIA) |

- **Namespace**: `soypete_tech`
- **Network**: Hardline connected via Ubiquiti switch and Dream Machine
- **Peer Discovery**: mDNS (requires same LAN broadcast domain)

## Setup

### Mac Studio

Runs the [EXO desktop app](https://github.com/exo-explore/exo). Set the namespace in app settings to `soypete_tech`.

### Spark Nodes (Ubuntu Linux)

```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc

# Install node/npm
sudo apt update && sudo apt install -y nodejs npm

# Clone and build
git clone https://github.com/exo-explore/exo ~/code/exo
cd ~/code/exo/dashboard && npm install && npm run build && cd ..

# Set namespace
echo 'export EXO_LIBP2P_NAMESPACE="soypete_tech"' >> ~/.bashrc
source ~/.bashrc
```

### Systemd Service (auto-start on Linux)

```bash
sudo tee /etc/systemd/system/exo.service << 'EOF'
[Unit]
Description=Exo Cluster Node
After=network.target tailscaled.service

[Service]
User=soypete
WorkingDirectory=/home/soypete/code/exo
Environment=HOME=/home/soypete
Environment=EXO_LIBP2P_NAMESPACE=soypete_tech
Environment=PATH=/home/soypete/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/bin/bash -lc 'cd /home/soypete/code/exo && uv run exo'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable exo
sudo systemctl start exo
```

**Manage the service:**
```bash
sudo systemctl status exo
sudo systemctl restart exo
sudo journalctl -u exo -f
```

### SSH Access to Spark 771e

Spark 771e is coupled to Spark f5ea — no direct Tailscale access. Hop through f5ea:

```bash
ssh soypete@100.87.122.109   # Mac -> Spark f5ea
ssh soypete@192.168.1.84     # Spark f5ea -> Spark 771e
```

## Connecting via Tailscale

Exo binds to `0.0.0.0:52415`, accessible on all interfaces including Tailscale.

```bash
# Check cluster state
curl -s http://100.87.122.109:52415/state | jq '.topology'

# List models
curl -s http://100.87.122.109:52415/v1/models | jq '.data[].id'

# Test inference
curl http://100.87.122.109:52415/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "mlx-community/Llama-3.3-70B-Instruct-4bit", "messages": [{"role": "user", "content": "Hello!"}]}'
```

**Note:** Tailscale uses /32 addresses (no broadcast domain), so mDNS peer discovery does NOT work over Tailscale. Nodes must be on the same LAN to discover each other.

## API Endpoints

- **Dashboard**: `http://<ip>:52415`
- **Cluster state**: `http://<ip>:52415/state`
- **Models**: `http://<ip>:52415/v1/models`
- **Inference**: `http://<ip>:52415/v1/chat/completions`

## Using OpenCode

Set in `~/.zshrc`:

```bash
SPARK_F5EA="100.87.122.109"
export EXO_API_URL="http://${SPARK_F5EA}:52415"
export EXO_API_BASE_URL="${EXO_API_URL}/v1"
```

Then run `opencode`. See `~/dotfiles/opencode/opencode.json` for provider config.

## Using exo-claude (Claude Code via LiteLLM proxy)

```bash
exo-models                                            # list available models
exo-claude mlx-community/Llama-3.3-70B-Instruct-4bit # run Claude Code
```

## Troubleshooting

**Nodes not discovering each other:**
- Confirm `EXO_LIBP2P_NAMESPACE` matches on all nodes and in the systemd service
- Nodes must be on the same LAN — Tailscale cannot be used for peer discovery
- Ubiquiti: set Gateway mDNS Proxy Service Scope to **"All"**

**Duplicate/phantom nodes or other weird dashboard behavior:**
- Update exo on all nodes — version mismatches cause Pydantic schema errors, crash loops, and duplicate node registrations
  ```bash
  # On each Spark:
  cd ~/code/exo && git pull origin main
  cd dashboard && npm install && npm run build && cd ..
  sudo systemctl restart exo
  ```
- Also update EXO.app on Mac Studio (Check for Updates in the app menu)
- If stale data persists after updating, clear event logs on all nodes and restart:
  ```bash
  rm -rf ~/.local/share/exo/event_log/
  ```

**Systemd service crashes on start:**
- Ensure `Environment=HOME=/home/soypete` is in the service file
- Check logs: `sudo journalctl -u exo -f`
- Try running manually: `cd ~/code/exo && uv run exo`

**Model not loading ("No instance found"):**
- Pre-download the model: `cd ~/code/exo && uv run exo download <model-id>`
- Spark 771e may need to download via Spark f5ea if it has no direct internet

**Check connectivity:**
```bash
curl -s http://100.87.122.109:52415/state | jq '.topology'
avahi-browse -a -t | head -20  # verify mDNS from a Spark
```
