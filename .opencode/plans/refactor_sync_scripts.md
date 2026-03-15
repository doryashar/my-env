# Refactoring Plan: setup.sh, sync_env.sh, and .env.zsh

## Overview

Consolidate scripts into clear responsibilities:
1. **setup.sh** - One-time setup, independent, no external sourcing
2. **sync_env.sh** - Orchestrate syncing with timestamp tracking
3. **.env.zsh** - Decide when to sync based on timing

---

## 1. setup.sh (merge with prerun.sh)

### Purpose
One-time initial setup. Completely independent - no sourcing other files.

### Responsibilities
- Clone public repo (`git@github.com:doryashar/my_env`) if doesn't exist
- Install Bitwarden CLI (inline functions)
- Authenticate with Bitwarden (OAuth2 or password prompt)
- Validate and install dependencies (git, curl, age, etc.)
- Install APT/PIP packages
- Install Docker
- Clone private encrypted repo if exists, **create it if not** (prompt for GitHub token)
- Run initial dotfiles sync
- Setup ZSH (z4h)
- Create default config files
- Create marker file `.env_installed`

### Key Changes
- **Embed logging functions inline** (no `source common_funcs`)
- Remove all git sync logic (moved to sync_env.sh)
- Add private repo creation with GitHub token prompt
- Make idempotent - safe to run multiple times
- Remove: `check_remote_updates()`, `check_local_changes()`, `update_from_remote()`, `prompt_push_changes()`

### Bug Fixes to Include
1. **Line 121,128 - `cd` without returning**: Use subshells for docker compose operations
   ```bash
   # Before
   cd "$ENV_DIR/docker/rclone-mount" || exit 1
   docker compose up -d
   
   # After
   (cd "$ENV_DIR/docker/rclone-mount" && docker compose up -d)
   ```

### Embedded Functions (inline, no sourcing)
```bash
# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO] $*${NC}"; }
debug() { [[ -n "${ENV_DEBUG:-}" ]] && echo -e "${PURPLE}[DEBUG] $*${NC}"; }
warning() { echo -e "${YELLOW}[WARNING] $*${NC}"; }
error() { echo -e "${RED}[ERROR] $*${NC}" >&2; exit 1; }
title() { echo -e "${BLUE}$*${NC}"; }

# Sanitize sensitive values in debug output
sanitize_debug() {
    echo "$1" | sed -E 's/(AGE_SECRET|BW_PASSWORD|BW_CLIENTID|BW_CLIENTSECRET|GITHUB_TOKEN|GH_TOKEN|API_KEY|TOKEN|BW_SESSION)=[^ ]+/\1=***HIDDEN***/g'
}
```

### Private Repo Creation Logic
```bash
create_private_repo() {
    local repo_url="$1"
    
    # Parse owner/repo from URL
    if [[ "$repo_url" =~ git@github\.com:([^/]+)/(.+)\.git ]]; then
        local owner="${BASH_REMATCH[1]}"
        local repo_name="${BASH_REMATCH[2]}"
    else
        error "Could not parse repository URL: $repo_url"
        return 1
    fi
    
    info "Creating private repository: $owner/$repo_name"
    
    # Try gh CLI first
    if command -v gh &>/dev/null; then
        if gh repo create "$owner/$repo_name" --private 2>/dev/null; then
            info "Repository created successfully!"
            return 0
        fi
    fi
    
    # Prompt for GitHub token
    local github_token=""
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        github_token="$GITHUB_TOKEN"
    else
        info "GitHub CLI not available or failed."
        read -p "Enter your GitHub Personal Access Token (with repo scope): " github_token
    fi
    
    if [[ -n "$github_token" ]]; then
        local response=$(curl -s -X POST \
            -H "Authorization: token $github_token" \
            -H "Accept: application/vnd.github.v3+json" \
            -d "{\"name\":\"$repo_name\",\"private\":true}" \
            "https://api.github.com/user/repos")
        
        if echo "$response" | jq -e '.clone_url' >/dev/null 2>&1; then
            info "Repository created successfully via API!"
            return 0
        else
            error "Failed to create repository: $(echo "$response" | jq -r '.message' 2>/dev/null)"
            return 1
        fi
    fi
    
    # Manual instructions fallback
    warning "Could not auto-create repository. Please create manually:"
    echo "1. Visit: https://github.com/new"
    echo "2. Repository name: $repo_name"
    echo "3. Set to Private"
    echo "4. Re-run setup.sh after creating"
    return 1
}
```

---

## 2. sync_env.sh

### Purpose
Orchestrate all syncing with timestamp tracking.

### Responsibilities
- Git push/pull for main repo (respect `DEFAULT_CONFLICT_STRATEGY`)
- Call `sync_dotfiles.sh`
- Call `sync_encrypted.sh`
- Track timestamps:
  - After `--check-only`: touch `tmp/last_check`
  - After full sync: touch `tmp/last_sync`
- Return status codes for .env.zsh

### Key Changes
- Remove `update_bashrc()` function
- Remove bashrc modification logic
- Add timestamp file management
- Simplify argument parsing (use `getopts`)
- Silent mode for `--check-only` (output only in debug verbosity)

### New Options
```
-c, --check-only    Check for updates, write tmp/last_check, return status (silent)
-s, --sync          Full sync (pull + push + dotfiles + encrypted)
-f, --force         Force sync even if recently synced
-d, --dotfiles      Sync dotfiles only
-e, --encrypted     Sync encrypted only
-p, --push          Push to remote
-l, --pull          Pull from remote
-h, --help          Show help
```

### Status Codes (for --check-only)
```
0 = no updates
1 = remote updates available
2 = uncommitted local changes
3 = both remote and local changes
```

### Bug Fixes to Include
1. **Line 262 - Unbound variable risk**: Handle missing keys explicitly
   ```bash
   # Before
   ${actions[$1]:-invalid_option} "$@"
   
   # After
   if [[ -v "actions[$1]" ]]; then
       ${actions[$1]} "$@"
   else
       invalid_option "$@"
   fi
   ```

2. **Duplicated git sync logic**: Already removed by merging into this file

### Simplified Argument Parsing
```bash
parse_args() {
    PERFORM_CHECK_ONLY=0
    PERFORM_SYNC=0
    PERFORM_FORCE=0
    PERFORM_DOTFILES=0
    PERFORM_ENCRYPTED=0
    PERFORM_PUSH=0
    PERFORM_PULL=0
    
    while getopts "csfdeplhu-:" opt; do
        case "$opt" in
            -)
                case "${OPTARG}" in
                    check-only) PERFORM_CHECK_ONLY=1 ;;
                    sync) PERFORM_SYNC=1 ;;
                    force) PERFORM_FORCE=1 ;;
                    dotfiles) PERFORM_DOTFILES=1 ;;
                    encrypted) PERFORM_ENCRYPTED=1 ;;
                    push) PERFORM_PUSH=1 ;;
                    pull) PERFORM_PULL=1 ;;
                    help) show_help; exit 0 ;;
                    *) error "Unknown option: --${OPTARG}" ;;
                esac
                ;;
            c) PERFORM_CHECK_ONLY=1 ;;
            s) PERFORM_SYNC=1 ;;
            f) PERFORM_FORCE=1 ;;
            d) PERFORM_DOTFILES=1 ;;
            e) PERFORM_ENCRYPTED=1 ;;
            p) PERFORM_PUSH=1 ;;
            l) PERFORM_PULL=1 ;;
            h) show_help; exit 0 ;;
            u) PERFORM_CHECK_ONLY=1 ;;  # backward compat
            *) show_help; exit 1 ;;
        esac
    done
}
```

### Git Sync with Conflict Strategy
```bash
git_sync_pull() {
    cd "$ENV_DIR" || return 1
    
    git fetch --quiet 2>/dev/null || return 1
    
    if git status | grep -q "behind"; then
        if [[ "$PERFORM_CHECK_ONLY" -eq 1 ]]; then
            return 1  # Signal: remote updates available
        fi
        
        # Respect DEFAULT_CONFLICT_STRATEGY
        case "$DEFAULT_CONFLICT_STRATEGY" in
            "remote")
                debug "Auto-pulling (strategy: remote)"
                git pull --ff-only origin master 2>/dev/null || git pull origin master
                ;;
            "ask")
                read -p "Remote updates available. Pull? (y/n) " -n 1 -r
                echo
                [[ $REPLY =~ ^[Yy]$ ]] && git pull origin master
                ;;
            *)
                debug "Skipping pull (strategy: $DEFAULT_CONFLICT_STRATEGY)"
                ;;
        esac
    fi
    return 0
}
```

### Timestamp Management
```bash
update_last_check() {
    mkdir -p "$ENV_DIR/tmp"
    touch "$ENV_DIR/tmp/last_check"
    debug "Updated last_check timestamp"
}

update_last_sync() {
    mkdir -p "$ENV_DIR/tmp"
    touch "$ENV_DIR/tmp/last_sync"
    debug "Updated last_sync timestamp"
}
```

---

## 3. .env.zsh

### Purpose
Decide WHEN to run sync_env.sh based on timing.

### Responsibilities
- Load config, env_vars, secrets, functions, aliases
- Check if interactive shell
- If `tmp/last_check` > `CHECK_INTERVAL_DAYS` old → run `sync_env.sh --check-only` in background
- If `tmp/last_sync` > `SYNC_INTERVAL_DAYS` old → prompt user
- Run display utilities (duf, neofetch, kuma_status, zerotier_clients)

### Key Changes
- Remove inline update check logic (lines 39-82)
- Replace with simple timestamp checks
- Fix `local` outside function bug
- Add helper function `file_age_days()`

### Bug Fixes to Include
1. **Line 39-40 - `local` outside function**: Use regular variables
   ```bash
   # Before
   local updates_detected_file="${ENV_DIR}/tmp/updates_detected"
   local lock_file="${ENV_DIR}/tmp/update_check.lock"
   
   # After
   updates_detected_file="${ENV_DIR}/tmp/updates_detected"
   lock_file="${ENV_DIR}/tmp/update_check.lock"
   ```

2. **Line 13,15,33 - Unquoted variables**: Quote all variable expansions
   ```bash
   # Before
   source ${ENV_DIR}/config/repo.conf
   
   # After
   source "${ENV_DIR}/config/repo.conf"
   ```

3. **Race condition**: Background process touches file, main shell checks immediately
   - Solution: Check happens on NEXT shell startup, not immediately

### New Helper Function (add to functions/helpers or inline)
```bash
file_age_days() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo 999999  # Very old if doesn't exist
        return
    fi
    local file_time=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
    local now=$(date +%s)
    echo $(( (now - file_time) / 86400 ))
}
```

### Simplified .env.zsh
```bash
# Enable debug prints with: export ENV_DEBUG=1
if [[ "$ENV_DEBUG" == "1" ]]; then
    env_debug() { echo "[DEBUG] $*" >&2; }
else
    env_debug() { :; }
fi

ENV_DIR="${ENV_DIR:-$HOME/env}"

# Helper function
file_age_days() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo 999999
        return
    fi
    local file_time=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
    echo $(( ($(date +%s) - file_time) / 86400 ))
}

# Load config
env_debug "Loading config from ${ENV_DIR}/config/repo.conf"
source "${ENV_DIR}/config/repo.conf"

env_debug "Loading env_vars from ${ENV_DIR}/env_vars"
source "${ENV_DIR}/env_vars"

# Load secrets if available
if [[ -f "${ENV_DIR}/private/secrets" ]]; then
    env_debug "Loading secrets from ${ENV_DIR}/private/secrets"
    source "${ENV_DIR}/private/secrets"
fi

# Source functions
env_debug "Sourcing functions from ${ENV_DIR}/functions/*"
for file in "${ENV_DIR}"/functions/*; do
    if [[ -f "$file" ]]; then
        env_debug "Sourcing $file"
        source "$file"
    fi
done

# Load aliases
source "${ENV_DIR}/aliases"

# Initialize zoxide
eval "$(zoxide init zsh)"

# Interactive shell checks
if [[ $- == *i* ]]; then
    env_debug "Interactive shell detected"
    
    # Check for updates (background, silent)
    check_interval="${CHECK_INTERVAL_DAYS:-1}"
    if [[ $(file_age_days "${ENV_DIR}/tmp/last_check") -ge $check_interval ]]; then
        env_debug "Running background update check"
        ( "${ENV_DIR}/scripts/sync_env.sh" --check-only 2>/dev/null ) &
    fi
    
    # Prompt for sync if overdue
    sync_interval="${SYNC_INTERVAL_DAYS:-7}"
    sync_age=$(file_age_days "${ENV_DIR}/tmp/last_sync")
    if [[ $sync_age -ge $sync_interval ]]; then
        echo "Last sync was $sync_age days ago. Run 'envsync' to sync."
    fi
    
    # Display utilities
    if [[ "$SHOW_DUFF" = "on" ]]; then
        (duf &)
    fi
    
    if [[ "$SHOW_NEOFETCH" = "on" ]]; then
        neofetch
    fi
    
    env_debug "Calling kuma_status"
    kuma_status
    
    env_debug "Calling zerotier_clients"
    zerotier_clients
fi
```

---

## 4. config/repo.conf Changes

### Add Configurable Intervals
```bash
# Sync timing (days)
CHECK_INTERVAL_DAYS="${CHECK_INTERVAL_DAYS:-1}"
SYNC_INTERVAL_DAYS="${SYNC_INTERVAL_DAYS:-7}"

# Conflict resolution: ask, local, remote, rename, ignore
DEFAULT_CONFLICT_STRATEGY="${DEFAULT_CONFLICT_STRATEGY:-ask}"
```

---

## 5. Additional Bug Fixes (from sync_encrypted.sh)

These are in files we're not modifying but worth noting:

1. **Line 532 - Password in process list**: 
   ```bash
   # Before
   export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)
   
   # After
   export BW_SESSION=$(bw unlock --passwordfile <(echo "$BW_PASSWORD") --raw 2>/dev/null)
   ```

2. **Line 117 - Process substitution with secret**:
   ```bash
   # Consider using temp file with restricted permissions instead of process substitution
   ```

---

## 6. File Deletions

After implementation:
- Delete `scripts/prerun.sh` (merged into setup.sh)

---

## 7. Implementation Order

1. Create `functions/helpers` with `file_age_days()` function
2. Update `config/repo.conf` with new config options
3. Rewrite `scripts/setup.sh` (merge prerun.sh, embed logging, add repo creation)
4. Rewrite `scripts/sync_env.sh` (simplify, add timestamps, silent mode)
5. Rewrite `dotfiles/.env.zsh` (simplify, fix bugs)
6. Update `aliases` (verify envsync alias exists)
7. Delete `scripts/prerun.sh`
8. Update tests

---

## 8. Testing Checklist

- [ ] Fresh machine: run setup.sh → repo clones, packages install, private repo created
- [ ] Existing machine: run setup.sh → idempotent, no errors
- [ ] sync_env.sh --check-only → silent, creates tmp/last_check, returns correct status
- [ ] sync_env.sh --sync → full sync, creates tmp/last_sync
- [ ] .env.zsh → loads without errors, no `local` warnings
- [ ] envsync alias works
- [ ] Background check runs after CHECK_INTERVAL_DAYS
- [ ] Sync prompt appears after SYNC_INTERVAL_DAYS
- [ ] DEFAULT_CONFLICT_STRATEGY respected during git conflicts
