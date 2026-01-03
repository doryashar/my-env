# Sync Dotfiles Script Documentation

## Overview

The `sync_dotfiles.sh` script synchronizes dotfiles between your local system and a git repository. It supports bidirectional syncing, automatic conflict resolution, and customizable link types.

## Location

`~/env/scripts/sync_dotfiles.sh`

## Features

- **Bidirectional Sync**: Forward sync (repo → system) and backward sync (system → repo)
- **Smart Conflict Resolution**: Based on modification time or user-specified strategy
- **Flexible Linking**: Supports both hard and soft symbolic links
- **Pattern Matching**: Supports wildcards and regex capture groups
- **Broken Link Detection**: Automatically removes broken symbolic links

## Usage

### Basic Usage

```bash
~/env/scripts/sync_dotfiles.sh [config_file]
```

**Default config**: `~/env/config/dotfiles.conf`

### With Custom Config

```bash
~/env/scripts/sync_dotfiles.sh ~/env/config/custom-dotfiles.conf
```

### Command Line Options

The script can also be invoked via `sync_env.sh`:

```bash
~/env/scripts/sync_env.sh --dotfiles_sync
```

## Configuration

### Config File Format

The configuration file uses a simple format with the following sections:

#### Global Settings

```bash
# Default link type (soft or hard)
DEFAULT_LINK_TYPE="soft"

# Default conflict resolution strategy
# Options: ask, local, remote, rename, ignore
DEFAULT_CONFLICT_STRATEGY="ask"
```

#### File Mappings

```bash
# Forward sync (repo → system): SOURCE => TARGET
dotfiles/.vimrc => ~/.vimrc
config/nvim => ~/.config/nvim

# Backward sync (system → repo): SOURCE <= TARGET
dotfiles/local_settings <= ~/.local_settings

# Wildcard patterns
dotfiles/* => ~/*
config/test/* => ~/.config/test/*

# Regex capture groups
config/(.*) => ~/.config/\$1
```

#### Mapping Syntax

- `=>`: Forward sync (copy/link from repo to system)
- `<=`: Backward sync (copy from system to repo)
- `*`: Wildcard matching
- `(.*)`: Capture group (reference with `$1`, `$2`, etc.)

## Conflict Resolution Strategies

### `ask` (Interactive)

Prompts the user to choose an action:

1. Keep local version (overwrite repository)
2. Use repository version (overwrite local)
3. Show diff
4. Rename local and use repository version
5. Ignore (keep both unchanged)

### `local`

Automatically keeps the local version.

### `remote`

Automatically uses the repository version.

### `rename`

Renames the local file with a timestamp and uses the repository version.

### `ignore`

Keeps both files unchanged.

## Functions

### `load_config(config_file)`

Parses and loads configuration from the specified file.

**Sets**: `DEFAULT_LINK_TYPE`, `DEFAULT_CONFLICT_STRATEGY`, `SOURCE_TO_TARGET`, `BACKWARD_SYNC`

### `sync_file(source, target, options)`

Syncs a single file from source to target.

**Options**:
- `link=soft|hard`: Type of link to create
- `conflict=ask|local|remote|rename|ignore`: Conflict resolution strategy

### `handle_conflict(source, target, strategy)`

Resolves conflicts based on the specified strategy.

### `create_link(source, target, link_type)`

Creates a hard or soft link between source and target.

### `process_backward_sync()`

Processes all backward sync mappings (system → repo).

### `sync_dotfiles()`

Main sync function that processes all mappings.

### `remove_all_broken_links(directory)`

Removes broken symbolic links in the specified directory.

## Examples

### Simple Configuration

```bash
# ~/.config/dotfiles.conf
DEFAULT_LINK_TYPE="soft"
DEFAULT_CONFLICT_STRATEGY="remote"

# Direct mappings
dotfiles/.bashrc => ~/.bashrc
dotfiles/.vimrc => ~/.vimrc

# Directory mappings
config/nvim => ~/.config/nvim
config/tmux => ~/.config/tmux
```

### Advanced Configuration

```bash
# ~/.config/dotfiles.conf
DEFAULT_LINK_TYPE="soft"
DEFAULT_CONFLICT_STRATEGY="ask"

# Forward sync
dotfiles/.zshrc => ~/.zshrc
config/nvim => ~/.config/nvim

# Wildcard patterns
config/* => ~/.config/*

# Capture groups - keep structure
config/(.*)/(.*) => ~/.config/\$1/\$2

# Backward sync - save local changes
dotfiles/local <= ~/.local_config

# Multiple wildcards
dotfiles/bin/* <= ~/bin/*
```

### Per-File Options

```bash
# Use hard link for critical file
dotfiles/.ssh/config => ~/.ssh/config link=hard conflict=remote

# Ask for conflicts in working files
dotfiles/.vimrc => ~/.vimrc link=soft conflict=ask
```

## Exit Codes

- `0`: Success
- `1`: Error

## Dependencies

- `git`: For version control
- `find`: For file pattern matching
- `ln`: For creating links
- `diff`: For comparing files

## Related Scripts

- `scripts/sync_env.sh`: Main synchronization script
- `scripts/setup.sh`: Setup script that calls sync_dotfiles

## Integration

### Running Automatically

Add to your `.zshrc`:

```bash
# Sync dotfiles on shell startup
if [[ -f "$HOME/env/scripts/sync_dotfiles.sh" ]]; then
    $HOME/env/scripts/sync_dotfiles.sh
fi
```

### Running via Cron

```bash
# Sync daily at 9 AM
0 9 * * * $HOME/env/scripts/sync_dotfiles.sh > /tmp/dotfiles_sync.log 2>&1
```

## Troubleshooting

### Broken Symlinks

The script automatically removes broken symlinks in your home directory.

### Permission Issues

Make sure the script has execute permissions:

```bash
chmod +x ~/env/scripts/sync_dotfiles.sh
```

### Conflicts

If conflicts occur, the script will prompt based on your `DEFAULT_CONFLICT_STRATEGY`. Use `ask` for interactive resolution.

## See Also

- [Setup Script](./SETUP_SCRIPT.md)
- [Sync Environment](./SYNC_ENV.md)
- [Sync Encrypted](./SYNC_ENCRYPTED.md)
