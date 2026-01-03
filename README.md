# My Environment Setup

This repository contains my essential Linux environment configuration, contains submodule:

- `private` (Private & Encrypted Repository): Contains sensitive data and configurations

## Quick Start

```bash
# Clone the repository
git clone git@github.com:doryashar/my_env.git ~/env
cd ~/env

# Run the pre-run check (handles first-time setup)
./scripts/prerun.sh

# Or run setup directly
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
│   ├── PRERUN_SCRIPT.md
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
│   ├── prerun.sh       # Pre-run check script
│   ├── setup.sh        # Main setup script
│   ├── sync_env.sh     # Environment sync wrapper
│   ├── sync_dotfiles.sh # Dotfiles synchronization
│   ├── sync_encrypted.sh # Encrypted files sync
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

### `scripts/prerun.sh`

Entry point script that checks installation status and keeps the environment synchronized.

**Features:**
- Checks if environment is installed
- Installs Bitwarden CLI if needed
- OAuth2 authentication for vault access
- Clones repository with API key
- Checks for remote updates
- Prompts to push local changes

**Usage:**
```bash
~/env/scripts/prerun.sh
```

### `scripts/setup.sh`

Main setup script that configures the complete environment.

**Features:**
- Installs APT and PIP packages
- Sets up Docker and compose services
- Installs ZSH and z4h
- Syncs dotfiles and encrypted files
- Installs fonts
- Sets up cron jobs

**Usage:**
```bash
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

## Configuration

### `config/repo.conf`

Main repository configuration:

```bash
# Remote git repository URL
REMOTE_URL="git@github.com:doryashar/my_env"
ENV_DIR="${HOME}/env"

# Bitwarden configuration
export BW_EMAIL="your-email@example.com"

# Private encrypted repository
PRIVATE_URL="git@github.com:doryashar/encrypted"

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
- [Prerun Script](./docs/PRERUN_SCRIPT.md) - Pre-run check documentation
- [Sync Dotfiles](./docs/SYNC_DOTFILES.md) - Dotfiles synchronization
- [Sync Encrypted](./docs/SYNC_ENCRYPTED.md) - Encrypted files synchronization

## License

This project is licensed under the MIT License - see the LICENSE file for details.
