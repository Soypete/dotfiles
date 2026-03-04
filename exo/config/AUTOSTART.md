# Exo Auto-start Configuration

This guide explains how to configure exo to run automatically at startup on your Spark machines using macOS launchd.

## Why Auto-start?

With auto-start configured:
- Exo starts automatically when you log in
- Exo restarts automatically if it crashes
- Your cluster is always available
- No manual intervention needed

## Setup Auto-start

### On Each Spark Machine:

```bash
# 1. Make sure exo is installed
ls ~/code/exo  # Should exist

# 2. Make sure uv is installed
which uv  # Should show path

# 3. Run setup script
~/dotfiles/exo/scripts/setup-autostart.sh
```

This script will:
1. Create a launchd plist file in `~/Library/LaunchAgents/`
2. Configure exo to run with the correct namespace
3. Set up logging to `~/dotfiles/exo/logs/`
4. Load the service immediately

## How It Works

The auto-start uses macOS **launchd**, which is the native service manager.

**Configuration file**: `~/dotfiles/exo/config/com.soypete.exo.plist`

Key settings:
- **RunAtLoad**: Starts exo when you log in
- **KeepAlive**: Restarts exo if it crashes
- **EnvironmentVariables**: Sets `EXO_LIBP2P_NAMESPACE` to `soypete-spark-cluster`
- **WorkingDirectory**: `~/code/exo`
- **Command**: `uv run exo`

## Managing the Service

### Check if exo is running:
```bash
launchctl list | grep com.soypete.exo
```

### View logs:
```bash
# Standard output
tail -f ~/dotfiles/exo/logs/exo-startup.log

# Errors
tail -f ~/dotfiles/exo/logs/exo-startup-error.log
```

### Stop the service:
```bash
launchctl unload ~/Library/LaunchAgents/com.soypete.exo.plist
```

### Start the service:
```bash
launchctl load ~/Library/LaunchAgents/com.soypete.exo.plist
```

### Remove auto-start completely:
```bash
~/dotfiles/exo/scripts/remove-autostart.sh
```

### Manually run exo (without auto-start):
```bash
cd ~/code/exo
export EXO_LIBP2P_NAMESPACE="soypete-spark-cluster"
uv run exo
```

## Troubleshooting

### Service won't start

1. Check logs for errors:
   ```bash
   cat ~/dotfiles/exo/logs/exo-startup-error.log
   ```

2. Verify exo is installed:
   ```bash
   ls ~/code/exo
   ```

3. Verify uv is installed:
   ```bash
   which uv
   ```

4. Try running manually first:
   ```bash
   cd ~/code/exo && uv run exo
   ```

### Service keeps restarting

Check error logs - there may be a configuration issue:
```bash
tail -f ~/dotfiles/exo/logs/exo-startup-error.log
```

### Can't connect to cluster

1. Check if exo is running:
   ```bash
   curl http://localhost:52415/state
   ```

2. Check launchd status:
   ```bash
   launchctl list | grep com.soypete.exo
   ```

3. Verify namespace matches on both Sparks:
   ```bash
   echo $EXO_LIBP2P_NAMESPACE
   # Should show: soypete-spark-cluster
   ```

## Updating Exo

If you update exo (git pull), the auto-start will automatically use the new version on next restart.

To restart exo after an update:
```bash
launchctl unload ~/Library/LaunchAgents/com.soypete.exo.plist
launchctl load ~/Library/LaunchAgents/com.soypete.exo.plist
```

Or reboot your Spark machine.
