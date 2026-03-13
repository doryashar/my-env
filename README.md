# My Environment Setup

Linux environment configuration with:
- Dotfiles management and sync
- Encrypted secrets via Bitwarden + age
- One-liner installation via curl
- Fork-friendly with upstream updates

## Quick Start

```bash
# One-liner install (recommended)
curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/setup.sh | bash

# Or with custom fork:
curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/setup.sh | ENV_URL=https://github.com/YOUR_USER/my-env bash

# Or clone manually:
git clone git@github.com:doryashar/my-env.git ~/env
cd ~/env
./scripts/setup.sh
```

## Prerequisites

- Git
- Curl
- Linux-based system
- Bitwarden CLI (for encrypted secrets)
- Docker (optional, for containerized services)

## What Gets Set Up

The setup script will configure:

- **Dotfiles**: Shell configurations (.zshrc, .vimrc, etc.)
- **Packages**: Development tools (APT, PIP packages)
- **Docker**: Container runtime and compose services
- **ZSH**: Zsh for Humans (z4h) as default shell
- **Fonts**: Custom font installation
- **Encrypted Secrets**: Bitwarden + age encryption
- **Cron Jobs**: Automated daily sync and backups

## Repository Structure

```
env/
├── AGENTS.md           # Agent instructions
├── README.md           # This documentation
├── aliases/            # Custom shell aliases
├── bin/                # Standalone binaries
├── config/             # Application configurations
│   ├── dotfiles.conf   # Dotfiles sync configuration
│   ├── repo.conf       # Repository configuration
│   └── crontab         # Cron job definitions
├── docker/             # Docker-compose files
│   ├── rclone-mount/   # Rclone mount service
│   └── zerotier/       # ZeroTier VPN service
├── docs/               # Documentation
│   ├── SETUP_SCRIPT.md
│   ├── SYNC_DOTFILES.md
│   └── SYNC_ENCRYPTED.md
├── dotfiles/           # Dotfiles (e.g., .bashrc, .vimrc)
├── functions/          # Shell functions
│   ├── common_funcs    # Common utility functions
│   ├── bw_funcs        # Bitwarden integration
│   └── monitors        # System monitoring functions
├── local/              # Local configurations
├── private/            # Private encrypted submodule (symlink)
├── scripts/            # Setup and utility scripts
│   ├── setup.sh        # Main setup script (entry point)
│   ├── sync_env.sh     # Environment sync wrapper
│   ├── sync_dotfiles.sh # Dotfiles synchronization
│   ├── sync_encrypted.sh # Encrypted files sync
│   ├── update_infrastructure.sh # Update scripts from upstream
│   ├── install_fonts.sh # Font installation
│   └── install_docker.sh # Docker installation
├── tests/              # Test suite
│   ├── setup_test.sh   # Setup script tests
│   └── sync_dotfiles_test.sh # Dotfiles sync tests
└── tmp/                # Temporary files
    ├── private/        # Decrypted private files (symlink)
    └── projects/       # GitHub projects
```

## Scripts

### `scripts/setup.sh`

Main entry point - self-cloning setup script that configures the complete environment.

**Features:**
- Self-clones if not running from repo (works via curl)
- Installs APT and PIP packages
- Sets up Docker and compose services
- Installs ZSH and z4h
- Syncs dotfiles and encrypted files
- Installs fonts
- Sets up cron jobs

**Usage:**
```bash
# Via curl (recommended)
curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/setup.sh | bash

# From repo
~/env/scripts/setup.sh
```

### `scripts/sync_env.sh`

Wrapper script for synchronizing all environment components.

**Usage:**
```bash
# Sync everything (dotfiles, encrypted, git)
~/env/scripts/sync_env.sh -d -e -l -p

# Check for updates only
~/env/scripts/sync_env.sh -u
```

### `scripts/sync_dotfiles.sh`

Synchronizes dotfiles between repository and home directory.

**Usage:**
```bash
~/env/scripts/sync_dotfiles.sh [config_file]
```

### `scripts/sync_encrypted.sh`

Synchronizes encrypted files using age encryption and Bitwarden.

**Usage:**
```bash
~/env/scripts/sync_encrypted.sh
```

### `scripts/update_infrastructure.sh`

Updates infrastructure scripts from upstream repository (useful for fork users).

**Usage:**
```bash
# Check for updates (dry run)
~/env/scripts/update_infrastructure.sh --dry-run

# Apply updates
~/env/scripts/update_infrastructure.sh
```

## For Fork Users

If you've forked this repository:

1. Set your fork URL in `config/repo.conf`:
   ```bash
   REMOTE_URL="git@github.com:YOUR_USER/my-env"
   UPSTREAM_URL="git@github.com:doryashar/my-env.git"  # for updates
   ```

2. Install from your fork:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/setup.sh | ENV_URL=https://github.com/YOUR_USER/my-env bash
   ```

3. Update infrastructure scripts from upstream:
   ```bash
   ~/env/scripts/update_infrastructure.sh
   ```

Your customizations in `config/`, `dotfiles/`, `aliases/`, `env_vars/`, and `private/` are never overwritten.

## Configuration

### `config/repo.conf`

Main repository configuration:

```bash
# Your fork URL
REMOTE_URL="git@github.com:YOUR_USER/my-env"
ENV_DIR="${HOME}/env"

# Bitwarden configuration
export BW_EMAIL="your-email@example.com"

# Private encrypted repository
PRIVATE_URL="git@github.com:YOUR_USER/encrypted"

# Upstream for infrastructure updates (keep pointing to original)
UPSTREAM_URL="git@github.com:doryashar/my-env.git"

# Sync timing (days)
CHECK_INTERVAL_DAYS=1
SYNC_INTERVAL_DAYS=7

# Merge conflict resolution strategy
DEFAULT_CONFLICT_STRATEGY="ask"

# Display settings
SHOW_DUFF=off
SHOW_NEOFETCH=on
```

### `config/dotfiles.conf`

Dotfiles synchronization configuration:

```bash
# Default link type (soft or hard)
DEFAULT_LINK_TYPE="soft"

# Default conflict resolution (ask, local, remote, rename, ignore)
DEFAULT_CONFLICT_STRATEGY="ask"

# File mappings
dotfiles/.zshrc => ~/.zshrc
config/nvim => ~/.config/nvim
config/tmux => ~/.config/tmux
```

### `config/crontab`

Automated tasks (example):

```bash
# Auto-sync dotfiles daily at 9 AM
0 9 * * * $HOME/env/scripts/sync_env.sh -d -e -l -p > /tmp/env_sync.log 2>&1

# Run backups daily at 2 AM
0 2 * * * $HOME/env/scripts/backup.sh > /tmp/backup.log 2>&1
```

## Security

- The `private` repository is encrypted using age
- Encryption keys are stored in Bitwarden
- Bitwarden authentication via OAuth2 or password
- Never commit unencrypted sensitive data

### Bitwarden Setup

1. Install Bitwarden CLI:
   ```bash
   brew install bitwarden-cli  # macOS
   sudo apt-get install bw     # Ubuntu/Debian
   ```

2. Login:
   ```bash
   bw login
   ```

3. Store required secrets:
   - `GITHUB_API_KEY`: GitHub token for repository access
   - `AGE_SECRET`: Age encryption private key

## Maintenance

### Update Environment

```bash
# Pull latest changes
cd ~/env
git pull

# Run setup again (idempotent)
./scripts/setup.sh
```

### Sync Changes

```bash
# Sync dotfiles to repository
~/env/scripts/sync_dotfiles.sh

# Sync encrypted files
~/env/scripts/sync_encrypted.sh

# Sync everything
~/env/scripts/sync_env.sh -d -e -p
```

### Run Tests

```bash
# Run all tests
cd ~/env/tests
./setup_test.sh
./sync_dotfiles_test.sh
```

## Environment Variables

- `ENV_DEBUG`: Set to `1` for debug output
- `ENV_DIR`: Override environment directory (default: `~/env`)
- `BW_EMAIL`: Bitwarden email address
- `BW_CLIENTID`: Bitwarden OAuth2 client ID (optional)
- `BW_CLIENTSECRET`: Bitwarden OAuth2 client secret (optional)
- `BW_SESSION`: Bitwarden session token (auto-generated)

## Documentation

- [Setup Script](./docs/SETUP_SCRIPT.md) - Main setup script documentation
- [Sync Dotfiles](./docs/SYNC_DOTFILES.md) - Dotfiles synchronization
- [Sync Encrypted](./docs/SYNC_ENCRYPTED.md) - Encrypted files synchronization

## License

This project is licensed under the MIT License - see the LICENSE file for details.
