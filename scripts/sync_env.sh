#!/bin/bash

# Declare variables
# If ENV_CONFIG_LOADED not set, load the config
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ENV_DIR=$(dirname "$SCRIPT_DIR")
CONFIG_FILE="$ENV_DIR/config/dotfiles.conf"

# Default configuration path
ENV_DIR="${ENV_DIR/#\~/$HOME}"
DEBUG=${ENV_DEBUG:-1}

## ====================================== ##
if ! type -t title &> /dev/null; then
    source $ENV_DIR/functions/common_funcs
fi
## ====================================== ##

# Function to display usage information
show_help() {
    title "ENV Synchronizer${NC}"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help                Show this help message"
    echo "  -i, --init                Initialize new dotfiles repository"
    echo "  -c, --config FILE         Use alternative config file"
    echo "  -r, --repo PATH           Set git repository path"
    echo "  -l, --pull                Pull changes from remote repository"
    echo "  -d, --dotfiles_sync       Sync dotfiles between local and repo"
    echo "  -e, --encrypted_sync      Sync encrypted files with remote repo"
    echo "  -p, --push                Push changes to remote repository"
    echo ""
}


# Initialize git repository for dotfiles
init_repo() {
    local repo_path="$1"
    
    if [[ -d "$repo_path/.git" ]]; then
        warning "Repository already initialized at $repo_path${NC}"
        return 0
    fi
    
    mkdir -p "$repo_path"
    cd "$repo_path" || exit 1
    
    git init
    touch README.md
    echo "# Dotfiles" > README.md
    echo "My personal dotfiles managed with Dotfiles Synchronizer" >> README.md
    
    # Create basic structure
    mkdir -p bash vim git
    
    git add README.md
    git commit -m "Initial commit"
    
    info "Repository initialized at $repo_path"
    echo "Edit your config file to add your dotfiles."
    
    return 0
}

# Sync with git repository
git_sync() {
    local direction="$1" # push or pull
    local repo_path="$2"
    cd "$repo_path" || exit 1
    
    # Check if there are changes
    if [[ -n "$(git status --porcelain)" ]]; then
        info "Changes detected in repository${NC}"
        git add .
        git commit -m "Auto-sync dotfiles $(date '+%Y-%m-%d %H:%M:%S')"
    fi
    
    if [[ "$direction" == "push" ]]; then
        if [[ -n "$REMOTE_URL" ]]; then
            # Check if remote is configured
            if ! git remote | grep -q origin; then
                git remote add origin "$REMOTE_URL"
            fi
            
            debug "Pushing changes to remote repository"
            git push origin master
        else
            warning "No remote URL configured. Skipping push."
        fi
    elif [[ "$direction" == "pull" ]]; then
        if [[ -n "$REMOTE_URL" ]]; then
            debug "Pulling changes from remote repository"
            
            # Check if remote is configured
            if ! git remote | grep -q origin; then
                git remote add origin "$REMOTE_URL"
            fi
            
            # Try to pull and merge
            if ! git pull --ff-only origin master ; then
                warning "Could not fast-forward merge. Trying to auto-merge...${NC}"
                
                if ! git pull origin master; then
                    error "Merge conflict detected."
                    
                    case "$DEFAULT_CONFLICT_STRATEGY" in
                        "ask")
                            warning "How would you like to handle git conflicts?${NC}"
                            echo "1) Manual resolution (open editor)"
                            echo "2) Keep local changes"
                            echo "3) Use remote changes"
                            echo "4) Abort merge"
                            
                            local choice
                            read -p "Enter choice [1-4]: " choice
                            
                            case "$choice" in
                                1) git mergetool ;;
                                2) git reset --hard HEAD ;;
                                3) git reset --hard origin/master ;;
                                4) git merge --abort ;;
                                *) 
                                    echo "Invalid choice"
                                    git merge --abort
                                    ;;
                            esac
                            ;;
                        "local")
                            git reset --hard HEAD
                            ;;
                        "remote")
                            git reset --hard origin/master
                            ;;
                        "rename")
                            git merge --abort
                            
                            # Create backup branch
                            local backup_branch="backup-$(date +%Y%m%d%H%M%S)"
                            git branch "$backup_branch"
                            info "Created backup branch: $backup_branch${NC}"
                            
                            # Force use remote
                            git reset --hard origin/master
                            ;;
                        "ignore")
                            git merge --abort
                            ;;
                        *)
                            git merge --abort
                            ;;
                    esac
                fi
            fi
        else
            warning "No remote URL configured. Skipping pull.${NC}"
        fi
    fi
    
    return 0
}

# Add the script to bashrc if not already there
update_bashrc() {
    local script_path="$(realpath "$0")"
    local bashrc="$HOME/.bashrc"
    
    if ! grep -q "$script_path" "$bashrc"; then
        info "Adding sync_env script to .bashrc${NC}"
        
        cat >> "$bashrc" << EOL

# Environment Synchronizer
if [ -f "$script_path" ] && [ "\$-" = *i* ]; then
    # Only run in interactive shells
    # Comment to disable auto-sync on shell startup:
    "$script_path" --dotfiles_sync --encrypted_sync --pull --push
    alias envsync="$script_path"
fi
EOL
        
        info "Added to .bashrc. You can now use 'envsync' command."
    else
        warning "Already added to .bashrc"
    fi
    
    return 0
}

# Main function
main() {
    local custom_config=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--config)
                custom_config="$2"
                shift 2
                ;;
            -r|--repo)
                ENV_DIR="$2"
                shift 2
                ;;
            -d|--dotfiles_sync)
                PERFORM_DOTFILES_SYNC=1
                shift
                ;;
            -e|--encrypted_sync)
                PERFORM_ENCRYPTED_SYNC=1
                shift
                ;;
            -p|--push)
                PERFORM_PUSH=1
                shift
                ;;
            -l|--pull)
                PERFORM_PULL=1
                shift
                ;;
            -i|--init)
                PERFORM_INIT=1
                shift
                ;;
            *)
                error "Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set config file path
    [[ -z "$custom_config" ]] || CONFIG_FILE="$custom_config"
    
    # Initialize if requested
    if [[ -n "$PERFORM_INIT" ]]; then
        title "Performing initialization"
        init_repo "$ENV_DIR"
        # TODO: create_default_config "$CONFIG_FILE"
        update_bashrc
    fi
    
    # If no action specified, show help
    if [[ -z "$PERFORM_INIT" && -z "$PERFORM_PULL" && -z "$PERFORM_DOTFILES_SYNC" && -z "$PERFORM_ENCRYPTED_SYNC" && -z "$PERFORM_PUSH" ]]; then
        show_help
    fi
    
    # TODO: depends on config OR flags,
    # TODO: if updated tell user the new version.

    # Perform actions
    [[ -n "$PERFORM_PULL" ]] && title "Git pulling" && git_sync "pull" "$ENV_DIR"
    [[ -n "$PERFORM_ENCRYPTED_SYNC" ]] && title "Encrypted files synching" && ${ENV_DIR}/scripts/sync_encrypted.sh
    [[ -n "$PERFORM_DOTFILES_SYNC" ]] && title "Dotfiles synching" && ${ENV_DIR}/scripts/sync_dotfiles.sh $CONFIG_FILE
    [[ -n "$PERFORM_PUSH" ]] && title "Git Pushing" && git_sync "push" "$ENV_DIR"
    
    return 0
}

# Start script
main "$@"
