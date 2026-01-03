# Prerun Script Documentation

## Overview

The `prerun.sh` script is the entry point for environment management. It checks if the environment is installed, performs initial setup if needed, and keeps the environment synchronized with the remote repository.

## Location

`~/env/scripts/prerun.sh`

## Features

- **Installation Check**: Verifies if the environment is properly installed
- **Vault CLI Setup**: Installs Bitwarden CLI if needed
- **OAuth2 Authentication**: Authenticates with Bitwarden for secure credential access
- **Repository Cloning**: Clones the environment repository with API key or SSH
- **Remote Updates**: Checks for and pulls updates from the remote repository
- **Local Changes**: Detects and prompts to push local changes

## Usage

### Basic Usage

```bash
cd ~/env/scripts
./prerun.sh
```

### Environment Variables

- `ENV_DEBUG`: Set to `1` to enable debug output
- `BW_CLIENTID`: Bitwarden OAuth2 client ID
- `BW_CLIENTSECRET`: Bitwarden OAuth2 client secret
- `BW_SESSION`: Bitwarden session token (auto-generated)
- `GITHUB_SSH_PRIVATE_KEY`: GitHub API token (auto-retrieved from Bitwarden)

## Functions

### `is_env_installed()`

Checks if the environment is installed by verifying:

1. The `ENV_DIR` directory exists
2. The `.env_installed` marker file exists

**Returns**:
- `0`: Environment is installed
- `1`: Environment is not installed

### `get_vault_cli()`

Installs the Bitwarden CLI if not already installed.

**Downloads**: `bw-linux` from GitHub releases

**Returns**:
- `0`: Success
- `1`: Failed to install

### `oauth2_authenticate()`

Authenticates with Bitwarden using OAuth2.

**Process**:
1. Checks login status with `bw status`
2. Performs OAuth2 login if unauthenticated
3. Unlocks the vault if locked
4. Sets `BW_SESSION` environment variable

**Returns**:
- `0`: Success
- `1`: Authentication failed

### `clone_repo_with_api_key()`

Clones the environment repository.

**Process**:
1. Attempts to get GitHub token from Bitwarden
2. Prompts for token if not found
3. Clones using HTTPS (with token) or SSH

**Returns**:
- `0`: Success
- `1`: Failed to clone

### `check_remote_updates()`

Checks if the remote repository has newer commits.

**Returns**:
- `0`: Remote is up-to-date
- `1`: Remote has updates

### `check_local_changes()`

Checks if there are uncommitted local changes.

**Returns**:
- `0`: No local changes
- `1`: Local changes exist

### `update_from_remote()`

Pulls updates from the remote repository.

**Process**:
1. Attempts fast-forward merge
2. Falls back to regular pull if needed

### `prompt_push_changes()`

Prompts the user to push local changes.

**Process**:
1. Shows warning about local changes
2. Prompts for confirmation
3. Adds, commits, and pushes changes if confirmed

## Installation Marker

After successful setup, a marker file is created:

```
~/env/.env_installed
```

This file is checked by `is_env_installed()` to determine if the environment is properly set up.

## Workflow

### First Run (Not Installed)

```
1. Check installation → Not installed
2. Get vault CLI
3. OAuth2 authenticate
4. Clone repository
5. Run setup.sh
6. Create .env_installed marker
```

### Subsequent Runs (Installed)

```
1. Check installation → Installed
2. Check for remote updates
3. Prompt to pull updates (if available)
4. Check for local changes
5. Prompt to push changes (if any)
```

## Exit Codes

- `0`: Success
- `1`: Error (exits immediately)

## Dependencies

- `git`: Version control
- `curl`: Downloading files
- `unzip`: Extracting archives
- `bw`: Bitwarden CLI (installed automatically if needed)

## Configuration

### Bitwarden OAuth2

To use OAuth2 authentication, set the following environment variables:

```bash
export BW_CLIENTID="your-client-id"
export BW_CLIENTSECRET="your-client-secret"
```

You can get these from [Bitwarden Developer Portal](https://bitwarden.com/developer/).

### GitHub Token

The script tries to retrieve the GitHub token from Bitwarden with the item name `GITHUB_API_KEY`.

If not found, it prompts for manual entry.

## Related Scripts

- `scripts/setup.sh`: Main setup script
- `scripts/sync_env.sh`: Environment synchronization
- `scripts/sync_encrypted.sh`: Encrypted files synchronization

## Examples

### Run prerun check

```bash
~/env/scripts/prerun.sh
```

### Run with debug output

```bash
ENV_DEBUG=1 ~/env/scripts/prerun.sh
```

### Automated check (in crontab)

```bash
# Check every hour
0 * * * * $HOME/env/scripts/prerun.sh > /tmp/prerun.log 2>&1
```

## Integration with Shell

Add to your `.zshrc` or `.bashrc`:

```bash
# Check environment on shell startup
if [[ -f "$HOME/env/scripts/prerun.sh" ]]; then
    $HOME/env/scripts/prerun.sh
fi
```

## See Also

- [Setup Script](./SETUP_SCRIPT.md)
- [Sync Environment](./SYNC_ENV.md)
