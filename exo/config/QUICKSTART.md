# Exo Cluster Quick Start Guide

Complete setup guide for your Spark cluster with Claude Code.

## Overview

- **Mac Studio**: Your main machine (runs Claude Code)
- **Spark 1**: 100.87.122.109 (compute node)
- **Spark 2**: 100.112.230.20 (compute node, accessible via Spark 1)
- **Service Manager**: launchd (macOS native, like systemd on Linux)

## Complete Setup Steps

### 1. Deploy Configuration (from Mac Studio)

```bash
~/dotfiles/exo/scripts/deploy-config-to-sparks.sh
```

This copies scripts and configs to `~/exo/` on both Sparks.

### 2. Setup Spark 1

```bash
# SSH to Spark 1
ssh soypete@100.87.122.109

# Install dependencies (if not already installed)
brew install uv node

# Clone exo
git clone https://github.com/exo-explore/exo ~/code/exo

# Build dashboard
cd ~/code/exo/dashboard
npm install
npm run build
cd ..

# Set cluster namespace
echo 'export EXO_LIBP2P_NAMESPACE="soypete-spark-cluster"' >> ~/.zshrc
source ~/.zshrc

# Setup auto-start with launchd
~/exo/scripts/setup-autostart.sh
```

### 3. Setup Spark 2

```bash
# From Spark 1, SSH to Spark 2
ssh soypete@100.112.230.20

# Repeat all commands from Step 2
brew install uv node
git clone https://github.com/exo-explore/exo ~/code/exo
cd ~/code/exo/dashboard && npm install && npm run build && cd ..
echo 'export EXO_LIBP2P_NAMESPACE="soypete-spark-cluster"' >> ~/.zshrc
source ~/.zshrc
~/exo/scripts/setup-autostart.sh
```

### 4. Verify Cluster (from Mac Studio)

```bash
# Check cluster status
curl http://100.87.122.109:52415/state | jq '.'

# Or use the helper
exo-status
```

### 5. Use Claude Code

```bash
# List available models
exo-models

# Run Claude Code with a model
exo-claude mlx-community/Llama-3.1-8B-Instruct-4bit
```

## What Gets Installed

### On Each Spark:

**Directory structure:**
```
~/exo/
├── config/
│   ├── com.soypete.exo.plist  # launchd service config
│   ├── MODELS.md              # Models guide
│   ├── README.md              # Setup docs
│   └── AUTOSTART.md           # Auto-start docs
├── scripts/
│   ├── setup-autostart.sh     # Install launchd service
│   ├── remove-autostart.sh    # Remove service
│   ├── status.sh              # Check cluster status
│   └── models.sh              # List models
└── logs/
    ├── exo-startup.log        # Service output
    └── exo-startup-error.log  # Service errors

~/code/exo/                    # Exo source code
```

**launchd service** (`com.soypete.exo`):
- Runs `uv run exo` from `~/code/exo`
- Starts at login
- Restarts if crashed
- Sets namespace to `soypete-spark-cluster`
- Logs to `~/exo/logs/`

## Managing the Cluster

### Check Service Status

```bash
# On a Spark
launchctl list | grep com.soypete.exo
```

### View Logs

```bash
# On a Spark
tail -f ~/exo/logs/exo-startup.log
tail -f ~/exo/logs/exo-startup-error.log
```

### Restart Service

```bash
# On a Spark
launchctl unload ~/Library/LaunchAgents/com.soypete.exo.plist
launchctl load ~/Library/LaunchAgents/com.soypete.exo.plist
```

### Check Cluster API

```bash
# From Mac Studio
curl http://100.87.122.109:52415/state
curl http://100.87.122.109:52415/models
```

## Troubleshooting

### Service won't start

```bash
# Check error logs
cat ~/exo/logs/exo-startup-error.log

# Try running manually
cd ~/code/exo
export EXO_LIBP2P_NAMESPACE="soypete-spark-cluster"
uv run exo
```

### Sparks not discovering each other

1. Check both have same namespace:
   ```bash
   echo $EXO_LIBP2P_NAMESPACE
   # Should be: soypete-spark-cluster
   ```

2. Check network connectivity:
   ```bash
   ping 100.112.230.20  # From Spark 1
   ping 100.87.122.109  # From Spark 2
   ```

3. Check both services are running:
   ```bash
   launchctl list | grep com.soypete.exo
   ```

### Model not downloading

1. Check internet connectivity on Sparks
2. Try manual download:
   ```bash
   pip install huggingface_hub
   huggingface-cli download mlx-community/Llama-3.1-8B-Instruct-4bit
   ```

## Benchmarking (Optional)

To measure and optimize your cluster performance:

```bash
# SSH to Spark 1
ssh soypete@100.87.122.109

# Run benchmark
cd ~/code/exo
uv run bench/exo_bench.py \
  --model mlx-community/Llama-3.1-8B-Instruct-4bit \
  --pp 128,256,512 \
  --tg 128,256 \
  --max-nodes 2 \
  --repeat 3 \
  --warmup 1 \
  --json-out bench/results.json
```

See **BENCHMARKING.md** for complete benchmarking guide.

## Reference

- **exo GitHub**: https://github.com/exo-explore/exo
- **MLX Models**: https://huggingface.co/mlx-community
- **launchd Guide**: `man launchd.plist` (on macOS)
- **Benchmarking**: See `BENCHMARKING.md` in this directory
