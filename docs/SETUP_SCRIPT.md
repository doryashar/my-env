# Setup Script Documentation

## Overview

The `setup.sh` script is the main environment setup script that configures a complete Linux development environment from scratch.

## Location

`~/env/scripts/setup.sh`

## Features

- **Dotfiles Management**: Synchronizes configuration files between the repository and the home directory
- **Package Installation**: Installs APT packages, Python packages (pip), and other development tools
- **Docker Setup**: Installs Docker and sets up Docker Compose services
- **Encrypted Secrets**: Syncs encrypted files via Bitwarden and age encryption
- **ZSH Configuration**: Installs Zsh for Humans (z4h) and sets up ZSH as the default shell
- **Cron Jobs**: Sets up automated tasks for daily syncing and backups
- **Binary Setup**: Extracts and configures binaries from the bin directory
- **Font Installation**: Installs custom fonts

## Usage

### Basic Usage

```bash
cd ~/env/scripts
./setup.sh
```

### Environment Variables

- `ENV_DEBUG`: Set to `1` to enable debug output
- `ENV_DIR`: Override the environment directory (default: `~/env`)
- `BW_EMAIL`: Bitwarden email address (set in `config/repo.conf`)

## Functions

### `validate_commands()`

Checks that required commands (git, curl) are installed.

### `generate_config()`

Creates the configuration file if it doesn't exist at `config/repo.conf`.

**Creates**: `~/env/config/repo.conf`

### `install_apt_packages()`

Installs common APT packages:

- build-essential, vim, neovim, tmux, zsh
- git, curl, wget, htop, tree
- ripgrep, fd-find, bat, exa
- unzip, zip, fontconfig, fc-cache

### `install_pip_packages()`

Installs common Python packages:

- python-lsp-server, black, flake8, pylint, neovim-remote

### `install_docker()`

Installs Docker if not already installed.

### `setup_docker_compose()`

Starts Docker Compose services:

- rclone-mount service (if `docker/rclone-mount/docker-compose.yml` exists)
- ZeroTier service (if `docker/zerotier/docker-compose.yml` exists)

### `setup_binaries()`

Extracts and sets up binaries:

- Makes AppImages executable
- Extracts tar.gz archives
- Adds `~/env/bin` to PATH

### `sync_encrypted_files()`

Calls `sync_encrypted.sh` to sync encrypted files via Bitwarden.

**New behavior**:
- Checks if the private repository exists (from `PRIVATE_URL` in config)
- If repository doesn't exist, prompts to create it
- Attempts to create the repository using `gh` CLI or GitHub API
- Falls back to manual instructions if automated creation fails
- Only syncs if repository exists

### `create_private_repo(repo_url)`

Creates a new private GitHub repository for encrypted files.

**Args**:
- `repo_url`: Repository URL (e.g., `git@github.com:owner/repo.git`)

**Creation methods** (tried in order):
1. `gh` CLI (GitHub CLI tool)
2. GitHub API (requires `GITHUB_TOKEN` or Bitwarden `GITHUB_API_KEY`)
3. Manual instructions

**Returns**:
- `0`: Success
- `1`: Failed

### `install_dotfiles()`

Calls `sync_dotfiles.sh` to sync configuration files.

### `setup_zsh()`

Installs and configures ZSH:

- Installs Zsh for Humans (z4h)
- Links `.zshrc` and `.zshenv`
- Sets ZSH as default shell

### `install_fonts()`

Installs fonts using `install_fonts.sh`.

### `clone_github_projects()`

Clones projects listed in the `projects` array.

### `setup_cron_jobs()`

Sets up cron jobs for automated tasks.

**Creates**: `~/env/config/crontab`

## Configuration Files

### `config/repo.conf`

Main configuration file:

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

### `config/crontab`

Cron jobs for automated tasks:

```bash
# Auto-sync dotfiles daily at 9 AM
0 9 * * * $HOME/env/scripts/sync_env.sh -d -e -l -p > /tmp/env_sync.log 2>&1

# Run backups daily at 2 AM
0 2 * * * $HOME/env/scripts/backup.sh > /tmp/backup.log 2>&1
```

## Exit Codes

- `0`: Success
- `1`: Error (exits immediately)

## Dependencies

- `git`: Version control
- `curl`: Downloading files
- `apt-get`: Package manager (Debian-based systems)
- `pip3`: Python package manager
- `zsh`: Z shell
- `docker`: Container runtime
- `bw`: Bitwarden CLI

## Related Scripts

- `scripts/prerun.sh`: Pre-run check script
- `scripts/sync_env.sh`: Environment synchronization
- `scripts/sync_dotfiles.sh`: Dotfiles synchronization
- `scripts/sync_encrypted.sh`: Encrypted files synchronization
- `scripts/install_fonts.sh`: Font installation
- `scripts/install_docker.sh`: Docker installation

## Examples

### Run setup with debug output

```bash
ENV_DEBUG=1 ~/env/scripts/setup.sh
```

### Re-run setup after cloning

```bash
cd ~/env/scripts
./setup.sh
```

## See Also

- [Prerun Script](./PRERUN_SCRIPT.md)
- [Sync Dotfiles](./SYNC_DOTFILES.md)
- [Sync Encrypted](./SYNC_ENCRYPTED.md)
