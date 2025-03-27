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
EOF
}


# Initialize git repository for dotfiles
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


# Sync with git repository (push/pull)
git_sync() {
    local direction="$1"
    local repo_path="$2"

    (cd "$repo_path" && {
        [[ -n "$(git status --porcelain)" ]] && {
            git add .
            git commit -m "Auto-sync dotfiles $(date '+%Y-%m-%d %H:%M:%S')"
        }

        if [[ -n "$REMOTE_URL" ]]; then
            git remote | grep -q origin || git remote add origin "$REMOTE_URL"
            [[ "$direction" == "push" ]] && git push origin master
            [[ "$direction" == "pull" ]] && git pull --ff-only origin master || {
                warning "Could not fast-forward merge. Trying auto-merge..."
                if ! git pull origin master; then
                    error "Merge conflict detected."
                    resolve_merge_conflict
                fi
            }
        else
            warning "No remote URL configured. Skipping $direction."
        fi
    })
}

# Handle merge conflicts
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

# Add the script to bashrc if not already present
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

# Main function
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
    )

    while [[ $# -gt 0 ]]; do
        ${actions[$1]:-invalid_option} "$@"
        shift
    done

    [[ -n "$PERFORM_INIT" ]] && init_repo "$ENV_DIR" && update_bashrc
    [[ -n "$PERFORM_PULL" ]] && git_sync "pull" "$ENV_DIR"
    [[ -n "$PERFORM_ENCRYPTED_SYNC" ]] && "$ENV_DIR/scripts/sync_encrypted.sh"
    [[ -n "$PERFORM_DOTFILES_SYNC" ]] && "$ENV_DIR/scripts/sync_dotfiles.sh" "$CONFIG_FILE"
    [[ -n "$PERFORM_PUSH" ]] && git_sync "push" "$ENV_DIR"
}

# Functions for argument handling
set_custom_config() { CONFIG_FILE="$2"; shift; }
set_env_dir() { ENV_DIR="$2"; shift; }
enable_dotfiles_sync() { PERFORM_DOTFILES_SYNC=1; }
enable_encrypted_sync() { PERFORM_ENCRYPTED_SYNC=1; }
enable_push() { PERFORM_PUSH=1; }
enable_pull() { PERFORM_PULL=1; }
enable_init() { PERFORM_INIT=1; }
invalid_option() { error "Unknown option: $1"; show_help; exit 1; }

# Start script
main "$@"
