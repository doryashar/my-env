# Sync Encrypted Script Documentation

## Overview

The `sync_encrypted.sh` script synchronizes encrypted files between your local system and a remote git repository using age encryption and Bitwarden for secret management.

## Location

`~/env/scripts/sync_encrypted.sh`

## Features

- **Age Encryption**: Uses age for modern file encryption
- **Bitwarden Integration**: Retrieves encryption keys from Bitwarden
- **Bi-directional Sync**: Pulls remote changes and pushes local changes
- **Merge Support**: Handles conflicts with three-way merge
- **Automatic Decryption**: Decrypts files to a working directory
- **Change Detection**: Uses file hashing to detect changes
- **Repo Validation**: Checks if remote repository exists before syncing

## Usage

### Basic Usage

```bash
~/env/scripts/sync_encrypted.sh
```

### Environment Variables

- `ENV_DEBUG`: Set to `1` to enable debug output
- `BW_EMAIL`: Bitwarden email address (set in `config/repo.conf`)
- `BW_SESSION`: Bitwarden session token (auto-generated)
- `BW_PASSWORD`: Bitwarden password (prompts if needed)
- `AGE_SECRET`: Age encryption key (retrieved from Bitwarden)

## Configuration

### Repository Settings

The script uses `PRIVATE_URL` from `config/repo.conf`:

```bash
PRIVATE_URL="git@github.com:your-username/encrypted.git"
```

**Important**: The repository URL is now sourced from `PRIVATE_URL` in `config/repo.conf`, not hardcoded.

### Paths

- **Remote Repository**: From `PRIVATE_URL` in config
- **Local Repository**: `~/env/tmp/private_encrypted`
- **Decrypted Directory**: `~/env/tmp/private`
- **Recipients File**: `~/env/tmp/private/age-recipients`

## Repository Check

The script now validates that the remote repository exists before attempting to sync.

### If Repository Does Not Exist

If the `PRIVATE_URL` repository doesn't exist, the script will:

1. **Exit immediately** with an error message
2. **Suggest running setup.sh** to create the repository
3. **Provide manual instructions** for creating the repo yourself

```
[ERROR] Private repository does not exist: git@github.com:user/repo.git

Please run setup.sh to create the private repository:
  ~/env/scripts/setup.sh

Or manually create a private repo and update PRIVATE_URL in ~/env/config/repo.conf
```

### Creating the Repository

Run the setup script to create the repository:

```bash
~/env/scripts/setup.sh
```

The setup script will:
1. Check if the repository exists
2. Prompt you to create it if it doesn't exist
3. Attempt to create it using `gh` CLI or GitHub API
4. Fall back to manual instructions if automated creation fails

### Bitwarden Items

The script expects these items in your Bitwarden vault:

| Item Name | Type | Description |
|-----------|------|-------------|
| `GITHUB_API_KEY` | Password | GitHub token for repository access |
| `AGE_SECRET` | Password | Age encryption private key |

## Workflow

### Initial Setup

```
1. Authenticate with Bitwarden
2. Clone encrypted repository
3. Decrypt all files
4. Create symlinks (e.g., ~/.ssh)
```

### Sync Workflow

```
1. Check for remote changes (git fetch)
2. Check for local changes (file hashing)
3. Handle four cases:
   - No changes: Do nothing
   - Only remote: Pull and decrypt
   - Only local: Encrypt and push
   - Both: Merge, encrypt, and push
```

## Functions

### `ensure_age_installed()`

Ensures the age encryption tool is installed. Attempts to install it using the system's package manager if not found.

### `encrypt_file(source, dest)`

Encrypts a single file or directory using age.

- **Directories**: Tar'd before encryption
- **Files**: Encrypted directly

### `decrypt_file(source, dest)`

Decrypts a single file or directory.

- **Archives**: Extracted after decryption
- **Files**: Moved to destination

### `encrypt_recursive(source_dir, dest_dir)`

Encrypts all files in a directory recursively.

**Skips**: Hidden files (starting with `.`)

### `decrypt_recursive(source_dir, dest_dir)`

Decrypts all `.age` files in a directory recursively.

**Removes**: `.age` extension from decrypted files

### `hashit(dir, hash_file)`

Generates a hash file for directory contents.

**Includes**: Permissions, timestamps, paths, and SHA256 hashes

### `has_changed(dir, hash_file)`

Checks if files in a directory have changed since the last hash.

**Returns**:
- `0`: No changes
- `1`: Changes detected

### `merge_changes(remote_dir, local_dir, merged_dir)`

Merges changes between remote and local directories.

**Process**:
1. Finds all unique files
2. Detects conflicts
3. Performs three-way merge if possible
4. Launches interactive merge tool for conflicts

**Supported Tools**: meld, kdiff3, vimdiff, diffuse, tkdiff, xxdiff

### `get_secret_keys()`

Authenticates with Bitwarden and retrieves secret keys.

**Sets**:
- `BW_SESSION`: Bitwarden session token
- `GITHUB_SSH_PRIVATE_KEY`: GitHub token
- `AGE_SECRET`: Age encryption key

## File Format

### Encrypted Files

Encrypted files have the `.age` extension:

```
config.tar.age      # Encrypted tar archive
ssh_key.age         # Encrypted file
```

### Hash Files

Hash files contain:

```
permissions timestamp filepath sha256hash
-rw------- 2025-01-01 file.txt abc123...
```

## Conflict Resolution

### Interactive Merge

When both remote and local have changes, the script:

1. Creates a temporary directory for remote files
2. Stashes local changes
3. Pulls and decrypts remote files
4. Attempts three-way merge
5. Launches merge tool for conflicts (if available)
6. Encrypts merged files
7. Pushes to remote

### Conflict Markers

If no merge tool is available, conflicts are marked with:

```
<<<<<<< LOCAL VERSION
Your changes
=======
Remote changes
>>>>>>> REMOTE VERSION
```

## Exit Codes

- `0`: Success or no changes
- `1`: Error (authentication, encryption, etc.)

## Dependencies

- `age`: Age encryption tool
- `bw`: Bitwarden CLI
- `git`: Version control
- `tar`: Archive creation
- `find`: File searching

## Installation

### Install Age

```bash
# Ubuntu/Debian
sudo apt-get install age

# macOS
brew install age

# From source
go install filippo.io/age/cmd/...@latest
```

### Install Bitwarden CLI

```bash
# Using npm
npm install -g @bitwarden/cli

# Using curl
curl -fsSL https://raw.githubusercontent.com/bitwarden/clients/main/scripts/install_bw.sh | bash
```

## Security

### Key Management

- Age private key is stored in Bitwarden as `AGE_SECRET`
- Never commit unencrypted secrets to git
- Recipients file (`age-recipients`) contains public keys for encryption

### Best Practices

1. Use strong Bitwarden master password
2. Enable 2FA on Bitwarden
3. Rotate encryption keys periodically
4. Never share the age private key

## Related Scripts

- `scripts/sync_env.sh`: Main synchronization script
- `scripts/setup.sh`: Setup script that calls sync_encrypted

## Examples

### Initial Decryption

```bash
~/env/scripts/sync_encrypted.sh
# First run: clones repo and decrypts all files
```

### Daily Sync

```bash
# Pull remote changes
~/env/scripts/sync_encrypted.sh

# The script will automatically detect and sync changes
```

### Manual Encryption

```bash
# Encrypt a single file
age -R ~/env/tmp/private/age-recipients -o file.txt.age file.txt

# Encrypt a directory
tar -czf - directory | age -R ~/env/tmp/private/age-recipients > directory.tar.age
```

### Manual Decryption

```bash
# Decrypt a single file
age -d -i <(echo "$AGE_SECRET") -o file.txt file.txt.age

# Decrypt a directory
age -d -i <(echo "$AGE_SECRET") -o - directory.tar.age | tar -xzf -
```

## Troubleshooting

### Authentication Failed

Make sure Bitwarden is set up:

```bash
# Check Bitwarden status
bw status

# Login manually
bw login

# Unlock
bw unlock
```

### Age Not Found

Install age:

```bash
sudo apt-get install age  # Ubuntu/Debian
brew install age          # macOS
```

### Merge Conflicts

The script will attempt automatic merge. If that fails:

1. Manual merge tools will launch (meld, kdiff3, etc.)
2. Or edit files with conflict markers manually
3. Run the script again to complete the sync

### SSH Keys Not Working

After decryption, the script creates symlinks:

```bash
~/.ssh -> ~/env/tmp/private/ssh
```

Make sure permissions are correct:

```bash
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
```

## See Also

- [Setup Script](./SETUP_SCRIPT.md)
- [Sync Environment](./SYNC_ENV.md)
- [Sync Dotfiles](./SYNC_DOTFILES.md)
