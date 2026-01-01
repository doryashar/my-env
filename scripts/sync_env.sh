#!/bin/bash

# set -euo pipefail  # Ensure robustness

# Declare variables
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ENV_DIR=$(dirname "$SCRIPT_DIR")
REPO_CONFIG_FILE="$ENV_DIR/config/repo.conf"
CONFIG_FILE="$ENV_DIR/config/dotfiles.conf"

# Default configuration path
ENV_DIR="${ENV_DIR/#\~/$HOME}"
DEBUG=${ENV_DEBUG:-1}

# Load external functions if needed
[[ $(type -t title) ]] || source "$ENV_DIR/functions/common_funcs"

# Source config file
[[ -f "$REPO_CONFIG_FILE" ]] && source "$REPO_CONFIG_FILE"

# Function to display usage information
show_help() {
    cat <<EOF
Usage: $0 [options]

Options:
  -h, --help                Show this help message
  -i, --init                Initialize new dotfiles repository
  -c, --config FILE         Use alternative config file
  -r, --repo PATH           Set git repository path
  -l, --pull                Pull changes from remote repository
  -d, --dotfiles_sync       Sync dotfiles between local and repo
  -e, --encrypted_sync      Sync encrypted files with remote repo
  -p, --push                Push changes to remote repository
  -u, --check-updates       Check for updates without syncing (quiet mode)
EOF
}

# Initialize a new git repository for dotfiles
#
# Args:
#   $1 - Repository path
#
# Returns:
#   0 - Success or already initialized
#
# Side Effects:
#   - Creates git repository
#   - Creates default directories (bash, vim, git)
#   - Creates initial README and commit
init_repo() {
    local repo_path="$1"

    if [[ -d "$repo_path/.git" ]]; then
        warning "Repository already initialized at $repo_path"
        return 0
    fi

    git init "$repo_path"
    cat <<EOF > "$repo_path/README.md"
# Dotfiles
My personal dotfiles managed with Dotfiles Synchronizer
EOF

    mkdir -p "$repo_path/bash" "$repo_path/vim" "$repo_path/git"
    git -C "$repo_path" add README.md
    git -C "$repo_path" commit -m "Initial commit"

    info "Repository initialized at $repo_path"
    echo "Edit your config file to add your dotfiles."
}

# Check for available updates without syncing or prompting
#
# Args:
#   $1 - Repository path
#
# Outputs:
#   "uncommitted" - Uncommitted changes detected
#   "remote" - Remote updates available
#   "none" - No updates
#
# Returns:
#   0 - Success
git_check_updates() {
    local repo_path="$1"
    local updates_available=0

    (cd "$repo_path" && {
        # Check for uncommitted changes
        if [[ -n "$(git status --porcelain)" ]]; then
            echo "uncommitted"
            return 0
        fi

        # Check for remote updates
        if [[ -n "$REMOTE_URL" ]]; then
            git remote | grep -q origin || git remote add origin "$REMOTE_URL"
            if git fetch --quiet 2>/dev/null; then
                local local_rev=$(git rev-parse HEAD)
                local remote_rev=$(git rev-parse @{upstream} 2>/dev/null) || return 0
                if [[ "$local_rev" != "$remote_rev" ]]; then
                    echo "remote"
                    return 0
                fi
            fi
        fi

        echo "none"
    })
}


# Sync with git repository (push or pull)
#
# Args:
#   $1 - Direction: "push" or "pull"
#   $2 - Repository path
#
# Returns:
#   0 - Success
#
# Side Effects:
#   - Commits uncommitted changes
#   - May push/pull from remote
#   - Prompts user for confirmation
git_sync() {
    local direction="$1"
    local repo_path="$2"

    (cd "$repo_path" && {
        [[ -n "$(git status --porcelain)" ]] && {
            info "Uncommitted changes detected. Committing changes..."
            git submodule foreach 'git add . && git commit -m "Auto-sync submodule $(date "+%Y-%m-%d %H:%M:%S")'
            git add .
            git commit -m "Auto-sync dotfiles $(date '+%Y-%m-%d %H:%M:%S')"
        }

        if [[ -n "$REMOTE_URL" ]]; then
            git remote | grep -q origin || git remote add origin "$REMOTE_URL"
            if [[ "$direction" == "push" ]]; then
                if [[ -n "$(git cherry -v)" ]]; then
                    read -p "Local changes detected. Do you want to push the changes? (y/n) " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        info "Pushing changes to git"
                        debug $(git push origin master 2>&1)
                    fi
                fi
            elif [[ "$direction" == "pull" ]]; then
                git fetch && git status | grep -q "behind" && {
                    read -p "An update is available. Do you want to pull the changes? (y/n) " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        info "Pulling changes from git"
                        debug $(git pull --ff-only origin master 2>&1)
                    fi
                }
            else
                warning "Could not fast-forward merge. Trying auto-merge..."
                if ! git pull origin master; then
                    error "Merge conflict detected."
                    resolve_merge_conflict
                fi
            fi
        else
            warning "No remote URL configured. Skipping $direction."
        fi
    })
}

# Resolve merge conflicts based on DEFAULT_CONFLICT_STRATEGY
#
# Uses global variable:
#   DEFAULT_CONFLICT_STRATEGY - Strategy to use (ask, local, remote, rename, ignore)
#
# Returns:
#   0 - Success
#
# Side Effects:
#   - May modify git state (reset, branch, merge --abort)
#   - May prompt user for input if strategy is "ask"
resolve_merge_conflict() {
    case "$DEFAULT_CONFLICT_STRATEGY" in
        "ask")
            warning "Git conflicts detected. Choose resolution:"
            echo "1) Manual resolution"
            echo "2) Keep local changes"
            echo "3) Use remote changes"
            echo "4) Abort merge"
            read -rp "Enter choice [1-4]: " choice
            case "$choice" in
                1) git mergetool ;;
                2) git reset --hard HEAD ;;
                3) git reset --hard origin/master ;;
                4) git merge --abort ;;
                *) git merge --abort ;;
            esac ;;
        "local") git reset --hard HEAD ;;
        "remote") git reset --hard origin/master ;;
        "rename")
            git merge --abort
            local backup_branch="backup-$(date +%Y%m%d%H%M%S)"
            git branch "$backup_branch"
            info "Created backup branch: $backup_branch"
            git reset --hard origin/master ;;
        "ignore") git merge --abort ;;
        *) git merge --abort ;;
    esac
}

# Add script to .bashrc for automatic execution
#
# Returns:
#   0 - Success or already present
#
# Side Effects:
#   - Appends script entry to ~/.bashrc
update_bashrc() {
    local script_path
    script_path="$(realpath "$0")"
    local bashrc="$HOME/.bashrc"

    grep -Fq "$script_path" "$bashrc" || {
        cat <<EOL >> "$bashrc"

# Environment Synchronizer
if [[ -f "$script_path" && "\$-" == *i* ]]; then
    "$script_path" --dotfiles_sync --encrypted_sync --pull --push
    alias envsync="$script_path"
fi
EOL
        info "Added to .bashrc. You can now use 'envsync' command."
    }
}

# Main entry point for the script
#
# Args:
#   Command line arguments (see show_help for options)
#
# Returns:
#   0 - Success
#   Non-zero on error
#
# Side Effects:
#   - May initialize repo
#   - May check/sync with git
#   - May sync dotfiles/encrypted files
main() {
    local custom_config=""
    # Initialize flags to prevent "unbound variable" errors

    declare -A actions=(
        [-h]=show_help [-help]=show_help
        [-c]=set_custom_config [--config]=set_custom_config
        [-r]=set_env_dir [--repo]=set_env_dir
        [-d]=enable_dotfiles_sync [--dotfiles_sync]=enable_dotfiles_sync
        [-e]=enable_encrypted_sync [--encrypted_sync]=enable_encrypted_sync
        [-p]=enable_push [--push]=enable_push
        [-l]=enable_pull [--pull]=enable_pull
        [-i]=enable_init [--init]=enable_init
        [-u]=enable_check_updates [--check-updates]=enable_check_updates
    )

    while [[ $# -gt 0 ]]; do
        ${actions[$1]:-invalid_option} "$@"
        shift
    done

    [[ -n "$PERFORM_INIT" ]] && init_repo "$ENV_DIR" && update_bashrc
    [[ -n "$PERFORM_CHECK_UPDATES" ]] && { git_check_updates "$ENV_DIR"; exit 0; }
    [[ -n "$PERFORM_PULL" ]] && git_sync "pull" "$ENV_DIR"
    [[ -n "$PERFORM_ENCRYPTED_SYNC" ]] && "$ENV_DIR/scripts/sync_encrypted.sh"
    [[ -n "$PERFORM_DOTFILES_SYNC" ]] && "$ENV_DIR/scripts/sync_dotfiles.sh" "$CONFIG_FILE"
    [[ -n "$PERFORM_PUSH" ]] && git_sync "push" "$ENV_DIR"
    debug Finished!
}

# Functions for argument handling
set_custom_config() { CONFIG_FILE="$2"; shift; }
set_env_dir() { ENV_DIR="$2"; shift; }
enable_dotfiles_sync() { PERFORM_DOTFILES_SYNC=1; }
enable_encrypted_sync() { PERFORM_ENCRYPTED_SYNC=1; }
enable_push() { PERFORM_PUSH=1; }
enable_pull() { PERFORM_PULL=1; }
enable_init() { PERFORM_INIT=1; }
enable_check_updates() { PERFORM_CHECK_UPDATES=1; }
invalid_option() { error "Unknown option: $1"; show_help; exit 1; }

# Start script
main "$@"
