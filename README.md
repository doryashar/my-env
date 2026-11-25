# My Environment Setup

Linux environment configuration with:
- Dotfiles management and sync
- Encrypted secrets via Bitwarden + age
- One-liner installation via curl
- Fork-friendly with upstream updates

## Quick Start

```bash
# One-liner install (recommended)
curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/install/setup.sh | bash

# Or with custom fork:
curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/install/setup.sh | ENV_URL=https://github.com/YOUR_USER/my-env bash

# Or clone manually:
git clone git@github.com:doryashar/my-env.git ~/env
cd ~/env
./scripts/install/setup.sh
```

On its first run the script asks for three values: the URL of your fork, the
private repository that holds the encrypted secrets, and the Bitwarden
email. Each can also be given as an environment variable (`REMOTE_URL`,
`PRIVATE_URL`, `BW_EMAIL`). Press Enter to keep the placeholder.

## Prerequisites

- Git
- Curl
- Linux-based system
- Bitwarden CLI (for encrypted secrets)
- Docker (optional, for containerized services)

## What Gets Set Up

The setup script will configure:

- **Dotfiles**: Shell configurations (.zshrc, .vimrc, etc.)
- **Packages**: APT packages; Python command-line tools through `pipx`
- **Binaries**: the Go SDK and the tools that are not kept in git are
  downloaded and verified against `config/binaries.tsv`
  (`scripts/install/install_binaries.sh`)
- **Docker**: Container runtime and compose services
- **ZSH**: Zsh for Humans (z4h) as default shell
- **Fonts**: Custom font installation
- **Encrypted Secrets**: Bitwarden + age encryption
- **Cron**: asks before replacing the installed crontab with
  `config/crontab`, and backs the installed one up first. Without
  `config/crontab` it writes a default file and tells you to install
  it. Nothing is scheduled automatically.

```
env/
├── AGENTS.md           # Agent instructions
├── README.md           # This documentation
├── aliases             # Custom shell aliases
├── bin/                 # Not in git: downloaded tools and symlinks; filled by setup.sh
├── config/             # Application configurations
│   ├── binaries.tsv    # Pinned downloads for setup.sh
│   ├── dotfiles.conf   # Dotfiles sync configuration (symlink mappings)
│   ├── repo.conf       # Personal repo config (gitignored)
│   ├── repo.conf.example  # Template for repo.conf
│   ├── systemd*/       # Unit files (system + user)
│   └── udev/           # Udev rules
├── docker/             # Docker-compose files
├── docs/               # Documentation (RESTORE.md = disaster runbook)
├── dotfiles/           # Dotfiles (.zshrc, .zshenv, ...)
├── env_vars            # Public env exports (work stuff lives in var/private/env_work)
├── functions/          # Shell function libraries (bw_funcs, common_funcs, ...)
├── private -> var/private  # Decrypted secrets (symlink)
├── scripts/
│   ├── install/        # One-time setup (setup.sh, docker, fonts)
│   ├── sync/           # Ongoing sync (sync_env, sync_dotfiles, sync_encrypted, ...)
│   ├── storagebox/     # StorageBox bisync/mount tooling
│   └── tools/          # Authored tools (monitor-switch, sysboard, …)
├── tests/              # Test suite (run_all_tests.sh)
├── var/                # Gitignored state: decrypted secrets, encrypted clone, change hashes
│   ├── private/        # Decrypted secrets (0600)
│   └── private_encrypted/  # Clone of the age-encrypted GitHub repo
└── tmp/                # Gitignored caches, locks and alert markers
```

## Scripts

### `scripts/install/setup.sh`

Main entry point - self-cloning setup script that configures the complete
environment. Also the disaster-recovery path (see docs/RESTORE.md).

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
curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/install/setup.sh | bash

# From repo
~/env/scripts/install/setup.sh
```

### `scripts/sync/sync_env.sh`

Wrapper script for synchronizing all environment components.

**Usage:**
```bash
# Sync everything (dotfiles, encrypted, git)
~/env/scripts/sync/sync_env.sh -d -e -l -p

# Check for updates only
~/env/scripts/sync/sync_env.sh -u
```

Local changes are committed only after a confirmation (or with
`ENV_AUTO_COMMIT=1`). Each step runs on its own: a failing step is
reported and the other steps still run.

### `scripts/sync/sync_dotfiles.sh`

Synchronizes dotfiles between repository and home directory
(symlink mappings in `config/dotfiles.conf`).

**Usage:**
```bash
~/env/scripts/sync/sync_dotfiles.sh [config_file]
```

### `scripts/sync/sync_encrypted.sh`

Synchronizes encrypted files using age encryption and Bitwarden.
After the first successful decrypt it caches the age identity to
`~/.config/age/secret`, so routine syncs need no vault unlock.

**Usage:**
```bash
~/env/scripts/sync/sync_encrypted.sh
```

### `scripts/sync/update_infrastructure.sh`

Updates infrastructure scripts from upstream repository (useful for fork users).

**Usage:**
```bash
# Check for updates (dry run)
~/env/scripts/sync/update_infrastructure.sh --dry-run

# Apply updates
~/env/scripts/sync/update_infrastructure.sh
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
   curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/install/setup.sh | ENV_URL=https://github.com/YOUR_USER/my-env bash
   ```

3. Update infrastructure scripts from upstream:
   ```bash
   ~/env/scripts/sync/update_infrastructure.sh
   ```

Your customizations in `config/`, `dotfiles/`, `aliases`, `env_vars`, and `var/private` are never overwritten.

## Configuration

### `config/repo.conf`

Main repository configuration. **Gitignored** — the committed template is
`config/repo.conf.example`; `setup.sh` copies it on first run. Never put
real emails or repo names in the tracked template:

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

Automated tasks (example). After the first successful encrypted sync,
the age identity is cached at `~/.config/age/secret`, so the cron job
runs unattended with no vault unlock:

```bash
# Auto-sync dotfiles daily at 9 AM
0 9 * * * $HOME/env/scripts/sync/sync_env.sh -d -e -l -p > /tmp/env_sync.log 2>&1
```

## Security

- The `private` repository is encrypted using age (content-encrypted
  `.age` files in a private GitHub repo)
- The age private key lives in Bitwarden (`AGE_SECRET`) and is cached to
  `~/.config/age/secret` (0600) after first decrypt
- The decrypted tree (`var/private/`) is 0600 and gitignored
- Editor debris (`*~`, `#*#`, `*.bak*`) is never encrypted or pushed
- `config/repo.conf` holds personal values and is gitignored
- Never commit unencrypted sensitive data
- The encrypted sync is a manual step (`envsync`); `secrets-health.timer`
  sends a Telegram message when the last backup is older than 48 hours
- Tokens reach curl through its config on stdin, never on a command line

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

   Items can be type-1 (password) or type-2 (secure note) — all fetches
   go through `bw_get_secret` (functions/common_funcs), which handles
   both.

## Maintenance

### Update Environment

```bash
# Pull latest changes
cd ~/env
git pull

# Run setup again (idempotent)
./scripts/install/setup.sh
```

### Sync Changes

```bash
# Sync dotfiles to repository
~/env/scripts/sync/sync_dotfiles.sh

# Sync encrypted files
~/env/scripts/sync/sync_encrypted.sh

# Sync everything
~/env/scripts/sync/sync_env.sh -d -e -p
```

### Run Tests

```bash
# Full suite (or pick suites with --only <name>; see --help)
bash tests/run_all_tests.sh --skip-docker
```

`bash tests/run_all_tests.sh --only <suite>` runs one suite. The Docker
suite (`--only docker`) runs the scripts in a clean Ubuntu container; it
needs Docker and its build context excludes secrets and vendored files
(`.dockerignore`). It does not pass yet: five of its seven suites test code
that was removed or assert nothing (follow-up 1 in
`docs/code_review_2026-08-28.md`), so leave it out with `--skip-docker`
until that is done.

### Disaster Recovery

New machine, one password. See **docs/RESTORE.md** for the full runbook.

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
