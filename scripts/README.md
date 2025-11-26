# new_claude.sh - Run Claude Code in Isolated Git Worktrees

This script creates isolated git worktrees and runs Claude Code locally or in containers.

## Features

- ✅ Creates isolated git worktrees for each session
- ✅ Automatic cleanup on exit
- ✅ Supports 3 execution modes: local, container, or devcontainer
- ✅ Persistent credentials across container sessions
- ✅ Auto-passes GitHub tokens to containers
- ✅ Based on official Anthropic devcontainer

## Usage

### Local Mode (Default)
```bash
./new_claude.sh [branch-name]
```
Runs Claude Code locally using your system installation.

### Container Mode
```bash
./new_claude.sh --container [branch-name]
```
Uses Docker sandbox template (`docker/sandbox-templates:claude-code`).

### Devcontainer Mode (Recommended for Isolation)
```bash
./new_claude.sh --devcontainer [branch-name]
```
Uses the official Anthropic devcontainer built from their Dockerfile.

## Environment Variables

### GitHub Token (Automatic)
If you have `GITHUB_API_TOKEN` set in your environment, it will automatically be passed to the container as `GH_TOKEN`:

```bash
export GITHUB_API_TOKEN=ghp_your_token_here
./new_claude.sh --container my-branch
```

Inside the container, Claude can use `$GH_TOKEN` for GitHub API operations like:
- Creating issues/PRs with `gh` CLI
- Accessing private repositories
- GitHub API requests

**Output when token is detected:**
```
>>> Passing GitHub token as GH_TOKEN
```

## First-Time Setup (Container Modes)

When using `--container` or `--devcontainer` for the first time:

1. **Theme Selection**: Choose your preferred color scheme
2. **Authentication**: Complete the OAuth flow (browser will open automatically)

Your credentials will be saved to a persistent Docker volume and reused across all subsequent sessions.

## How It Works

### Worktree Creation
- Creates `.worktrees/<branch-name>` directory
- Branches from your current branch (not an orphan)
- Mounts parent repository's `.git` directory for remotes access
- Automatic cleanup when you exit Claude

### Git Remote Access
The script automatically mounts the parent repository's `.git` directory so that:
- `git remote -v` works in containers
- `git add`, `git commit`, `git push` all work
- `gh pr create` and other GitHub CLI commands work
- All git operations have full access to remotes and history

**Note**: The `.git` directory is mounted read-write to allow git worktree operations. Changes are isolated to the worktree branch and cleaned up on exit.

### Credentials (Container Modes)
Following the approach from [cuti](https://github.com/nociza/cuti):

- **Separate credentials for containers**: Can't share host credentials with Linux containers
- **Persistent Docker volumes**:
  - Devcontainer: `claude-devcontainer-config`
  - Sandbox: `claude-sandbox-config`
- **One-time setup**: Authenticate once, reuse forever

## Examples

```bash
# Quick local session
./new_claude.sh my-feature

# Isolated container session with GitHub access
export GITHUB_API_TOKEN=ghp_xxxxx
./new_claude.sh --devcontainer bugfix-123

# Custom branch name with container
./new_claude.sh --container feature/new-api
```

## Cleanup

- Worktrees are automatically removed when Claude exits
- To manually clean up persistent credentials:
  ```bash
  docker volume rm claude-devcontainer-config
  docker volume rm claude-sandbox-config
  ```

## Requirements

- Git with worktree support
- Docker (for container modes)
- Claude Code installed (for local mode)
- Optional: `GITHUB_API_TOKEN` for GitHub operations in containers

## Troubleshooting

### "Welcome to Claude Code" appears every time
You need to complete the full onboarding flow INCLUDING authentication. Simply selecting a theme isn't enough - you must also complete `claude login`.

### Docker daemon not running
```bash
sudo systemctl start docker  # Linux
# or
open -a Docker  # macOS
```

### Can't build devcontainer image
The script automatically downloads the official Dockerfile and builds it. Ensure you have internet access and Docker is running.

### GitHub token not working in container
1. Verify it's set: `echo $GITHUB_API_TOKEN`
2. Check the script output for "Passing GitHub token as GH_TOKEN"
3. Inside container, verify: `echo $GH_TOKEN`

## Test Scripts

- `test_claude_container.sh` - Tests credential mounting
- `test_devcontainer_full.sh` - Full devcontainer test with build
- `test_persistent_volume.sh` - Tests credential persistence
- `test_github_token.sh` - Tests GitHub token passing (requires `GITHUB_API_TOKEN` set)
- `test_git_remote_simple.sh` - Tests git remote access in containers
- `test_git_remotes.sh` - Detailed git remote analysis
- `test_git_operations.sh` - Tests git add/commit/status operations

## Credits

- Inspired by [cuti](https://github.com/nociza/cuti)'s approach to container credential management
- Uses official Anthropic devcontainer Dockerfile
