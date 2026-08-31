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

- **opencode/**: OpenCode AI editor configuration
  - `opencode.json`: Model, LSP, provider, skill permissions, and custom commands
  - `tui.json`: TUI keybinds (`display_thinking` → `<leader>i`)
  - `skills/`: Global OpenCode skills (graphify, llmwiki, mempalace).
    See `skills/HOW_TO_WRITE_SKILLS.md` for the format and permission model.
  - Providers:
    - `ray` — the `spark-vllm/` cluster (spark-f5ea) at
      `http://100.87.122.108:8000/v1` on the haikei tailnet
      (`http://100.87.122.109:8000/v1` on the other tailnet — same machine)
    - `pedrogpt` — llama.cpp on RTX 5090 via MagicDNS `http://pedrogpt:8000/v1`
    - `pedrogpt-haikei` — the same box at `http://100.121.229.113:8000/v1`,
      for when the client is on the haikei tailnet
  - Both pedrogpt entries address ONE machine: only one model is resident at a
    time (32GB VRAM), so switching triggers a ~18GB reload.
  - Default model: `ray/deepseek-ai/DeepSeek-V4-Flash-0731`. MiniMax is no longer
    listed in `opencode.json` — it is not running. To go back to it, re-add the
    model entry and switch `START_SCRIPT` (see `spark-vllm/RUNBOOK.md`).
  - Keep `context + output` under the server's `--max-model-len`.

- **spark-vllm/**: Two-node Spark vLLM cluster (serves the OpenCode provider above)
  - `RUNBOOK.md`: Start/restart, QSFP static-IP persistence, troubleshooting,
    GGUF post-mortem, model notes
  - `start-cluster.sh`: MiniMax-M2.5-AWQ serve command (known-good fallback)
  - `start-cluster-deepseek.sh`: DeepSeek-V4-Flash-0731 via the upstream recipe
    runner (284B MoE, ~167GB, tp=2 across both nodes, B12X/SM121 container)
  - `start-cluster-gguf.sh`: GGUF variant — guarded off, unservable on vLLM
  - `cleanup-containers.sh`: Wipes containers on both nodes for clean Ray state
  - `hf-download-gguf.sh`: Download + shard-merge + rsync to worker
  - `systemd/vllm-cluster.service`: One unit; the model is selected by
    `START_SCRIPT` in `/etc/default/vllm-cluster` (see `vllm-cluster.env.example`)
  - Prefer upstream `recipes/*.yaml` over hand-written serve commands for new
    models — they carry the container image, env, and mods. Keep the
    `~/spark-vllm-docker` checkout current.
  - Scripts run from `/home/soypete/` on spark-f5ea, scp'd from here —
    see RUNBOOK "Deploying these scripts to the Sparks"

- **crush/**: Crush AI editor configuration
  - `crush.json`: LSP configurations for Go, TypeScript, and Nix
  - Defines local LLM providers (pedro on tailnet, ollama locally)
  - Tool permissions: view, ls, grep, edit, mcp_context7_get-library-doc

### Installation Flow

The `startup.sh` script handles complete environment setup:
1. Installs oh-my-zsh
2. Installs webi.sh package manager
3. Installs core tools via webi: jq, gh, terraform, go, ripgrep, node
4. Platform-specific setup:
   - macOS (arm64): Installs neovim, python, brew, uv, ruff, podman, fzf, 1password-cli, macmon, node
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
- `$KUBECONFIG`: `~/.foundry/kubeconfig` (managed by Foundry CLI)
- `$EDITOR`: `nvim` (local), `vim` (SSH)
- `$SSH_AUTH_SOCK`: 1Password SSH agent socket
- `$NVM_DIR`: `$HOME/dotfiles/nvm` (Node Version Manager)

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
