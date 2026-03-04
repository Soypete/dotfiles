# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository for development environments, primarily focused on macOS (with some Linux support). The configurations are shared on Twitch (twitch.tv/soypete01) and support both personal and non-proprietary projects.

## Architecture

### Configuration Structure

The repository follows a modular structure where each tool has its own directory:

- **nvim/**: Neovim configuration using LazyVim plugin manager
  - `init.lua`: Main entry point, loads config modules from `lua/config/`
  - `lua/config/options.lua`: Editor settings (tabs, line numbers, spell check, Go formatting on save)
  - `lua/config/keymaps.lua`: Custom key mappings
  - `lua/config/lazy.lua`: LazyVim plugin manager setup
  - `lua/config/go.lua`: Go-specific configuration
  - Uses LazyVim as base configuration framework
  - Auto-runs gofmt + goimports on save for Go files

- **zsh/**: ZSH shell configuration
  - `zshrc`: Main ZSH config using oh-my-zsh with awesomepanda theme
  - `zsh_profile`: Environment variables and secrets sourcing
  - Sets `$XDG_CONFIG_HOME` to `$HOME/dotfiles` (affects config file locations)
  - Configured plugins: git, vscode, golang, history, kubectl, macos, man, rust
  - Key aliases: `docker` → `podman`, `python` → `python3`

- **bash/**: Bash configuration (less actively used)
  - `bashrc`: Basic bash configuration

- **vim/**: Traditional vim configuration
  - `vimrc`: Standalone vim setup (pre-neovim)

- **ghostty/**: Ghostty terminal emulator configuration
  - Custom ToyChest theme with specific color palette
  - Font size: 24, non-native fullscreen mode

- **crush/**: Crush AI editor configuration
  - `crush.json`: LSP configurations for Go, TypeScript, and Nix
  - Defines local LLM providers (pedro on tailnet, ollama locally)
  - Tool permissions: view, ls, grep, edit, mcp_context7_get-library-doc

- **exo/**: Exo cluster configuration for distributed AI inference
  - `config/`: Configuration files and documentation
  - `scripts/`: Management scripts (start-cluster.sh, status.sh, models.sh)
  - `logs/`: Cluster log files
  - Cluster namespace: `soypete_tech`
  - Hardware: Mac Studio + 2x Spark nodes (coupled) on 192.168.1.x LAN
  - API endpoint: `http://localhost:52415`

### Installation Flow

The `startup.sh` script handles complete environment setup:
1. Installs oh-my-zsh
2. Installs webi.sh package manager
3. Installs core tools via webi: jq, gh, terraform, go, ripgrep, node
4. Platform-specific setup:
   - macOS (arm64): Installs neovim, python, brew, uv, ruff, podman, fzf, 1password-cli, macmon, node (for exo)
   - Linux: Uses apt for vim, podman, fzf, 1password-cli
5. Initializes podman machine
6. Creates symlinks for dotfiles:
   - `~/.bashrc` → `dotfiles/bash/bashrc`
   - `~/.zshrc` → `dotfiles/zsh/zshrc`
   - `~/.zsh_profile` → `dotfiles/zsh/zsh_profile`
7. Creates `~/code/` directory for projects

### Key Environment Variables

- `$XDG_CONFIG_HOME`: `$HOME/dotfiles` (affects where config files are loaded from)
- `$GOPATH`: `${HOME}/code/go`
- `$KUBECONFIG`: `~/kubeconfig`
- `$EDITOR`: `nvim` (local), `vim` (SSH)
- `$SSH_AUTH_SOCK`: 1Password SSH agent socket
- `$NVM_DIR`: `$HOME/dotfiles/nvm` (Node Version Manager)
- `$EXO_API_URL`: `http://localhost:52415` (exo cluster API)
- `$EXO_LIBP2P_NAMESPACE`: `soypete_tech` (cluster isolation)
- `$ANTHROPIC_BASE_URL`: `${EXO_API_URL}/v1` (Claude Code with exo backend)
- `$ANTHROPIC_AUTH_TOKEN`: Empty (local cluster, no auth needed)
- `$ANTHROPIC_MODEL`: Set to desired model ID from exo cluster

## Common Development Commands

### Initial Setup

```bash
./startup.sh  # Complete environment setup (run on new machine)
```

### Shell Configuration

```bash
source ~/.zshrc    # Reload ZSH configuration
re                 # Alias for above
```

### Editor Shortcuts

```bash
nvim              # Open neovim
editz             # Edit ~/.zsh_profile
editc             # Edit ~/.zshrc
editv             # Edit ~/.vimrc
editn             # Edit neovim config
```

### Neovim Keybindings

**File Navigation (Telescope):**
- `<leader>ff` - Find files
- `<leader>fg` - Live grep
- `<leader>fb` - Buffers
- `<leader>fh` - Help tags

**LSP + Telescope:**
- `gr` - Find references
- `gd` - Go to definition
- `gi` - Go to implementations
- `gt` - Go to type definitions
- `<leader>ss` - Document symbols
- `<leader>sS` - Workspace symbols
- `<leader>sd` - Document diagnostics
- `<leader>sD` - Workspace diagnostics

**NerdTree:**
- `<leader>n` - Focus NerdTree
- `<C-n>` - Open NerdTree
- `<C-t>` - Toggle NerdTree
- `<C-f>` - Find current file in NerdTree

### Container Management

```bash
podman machine init   # Initialize podman VM
podman machine start  # Start podman VM
docker [cmd]          # Aliased to podman
```

### Exo Cluster Management

```bash
exo-start      # Start the exo cluster
exo-status     # Check cluster status and health
exo-models     # List available models
exo-claude     # Run Claude Code with exo backend (alias for 'claude')
```

**Setup exo cluster on Sparks:**

1. Deploy configs from Mac Studio:
   ```bash
   ~/dotfiles/exo/scripts/deploy-config-to-sparks.sh
   ```

2. On each Spark, install exo:
   ```bash
   # Clone and build
   git clone https://github.com/exo-explore/exo ~/code/exo
   cd ~/code/exo/dashboard && npm install && npm run build && cd ..

   # Set namespace
   echo 'export EXO_LIBP2P_NAMESPACE="soypete-spark-cluster"' >> ~/.zshrc
   source ~/.zshrc

   # Setup launchd auto-start
   ~/exo/scripts/setup-autostart.sh
   ```

3. Run Claude Code from your Mac Studio:
   ```bash
   # Show available models
   exo-claude

   # Run with specific MLX model
   exo-claude mlx-community/Llama-3.1-8B-Instruct-4bit
   exo-claude mlx-community/Qwen2.5-Coder-7B-Instruct-4bit
   ```

**Manage exo service on Sparks:**
```bash
# Check status
launchctl list | grep com.soypete.exo

# Stop
launchctl unload ~/Library/LaunchAgents/com.soypete.exo.plist

# Start
launchctl load ~/Library/LaunchAgents/com.soypete.exo.plist

# View logs
tail -f ~/dotfiles/exo/logs/exo-startup.log
```

**Cluster Details:**
- Dashboard: http://100.87.122.109:52415 (or localhost if running locally)
- API: http://100.87.122.109:52415/v1 (OpenAI-compatible)
- Nodes: 2x Spark machines at 100.87.122.109 (hardline connected via Ubiquiti)
- Namespace: `soypete-spark-cluster` (prevents accidental cluster joining)
- Supported Models: MLX-format models from `mlx-community` on Hugging Face

**Model Recommendations:**
- See `exo/config/MODELS.md` for complete models guide
- Recommended: `mlx-community/Llama-3.1-8B-Instruct-4bit`
- Code: `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit`
- Models auto-download from Hugging Face on first use

## Working with This Repository

### Modifying Configurations

When editing configuration files, note that:
- Changes to `zsh/zshrc` or `zsh/zsh_profile` require running `source ~/.zshrc` to take effect
- Neovim configs are in Lua (not Vimscript)
- The repository uses symlinks, so editing `~/.zshrc` directly edits the repository file

### LSP Configuration

The crush.json file defines LSP servers. When adding support for new languages:
- Add LSP command and arguments under `lsp` key
- Specify any required environment variables (e.g., `GOTOOLCHAIN` for Go)

### Security

- Secrets are stored in `~/.secrets` (not tracked in git)
- SSH uses 1Password agent for key management
- `.gitignore` excludes: lock files, nvim/lazyvim.json, and various tool-specific configs
