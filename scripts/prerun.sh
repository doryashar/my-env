#!/bin/bash

#########################################################################
# ENV Pre-Run Script
#
# Entry point script that checks if environment is installed and
# performs initial setup if needed.
#
# Features:
# - Checks if environment is installed
# - OAuth2 authentication for vault
# - Clones repo with API key if needed
# - Runs setup.sh
# - Checks for remote updates
# - Prompts to push local changes
#########################################################################

# Common Functions
# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

info() {
    local message="$*"
    echo -e "${GREEN}[INFO] $message${NC}"
}

debug() {
    local message="$*"
    if [[ -n "$ENV_DEBUG" ]]; then
        echo -e "${PURPLE}[DEBUG] $message${NC}"
    fi
}

warning() {
    local message="$*"
    echo -e "${YELLOW}[WARNING] $message${NC}"
}

title() {
    local message="$*"
    echo -e "${BLUE}$message${NC}"
}

error() {
    local message="$*"
    echo -e "${RED}[ERROR] $message${NC}"
    exit 1
}

# Get script directory and ENV_DIR
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ENV_DIR=$(dirname "$SCRIPT_DIR")

# Source common functions if available
if [[ -f "$ENV_DIR/functions/common_funcs" ]]; then
    source "$ENV_DIR/functions/common_funcs"
fi

# Check if environment is installed
#
# Returns:
#   0 - Environment is installed
#   1 - Environment is not installed
is_env_installed() {
    # Check if the env directory exists
    if [[ ! -d "$ENV_DIR" ]]; then
        return 1
    fi

    # Check if setup has been run (look for marker file)
    local marker_file="$ENV_DIR/.env_installed"
    if [[ ! -f "$marker_file" ]]; then
        return 1
    fi

    return 0
}

# Get vault CLI (Bitwarden)
#
# Returns: 0 - Success, 1 - Failed
get_vault_cli() {
    info "Getting Vault CLI (Bitwarden)..."

    if command -v bw &> /dev/null; then
        debug "Bitwarden CLI already installed"
        return 0
    fi

    # Install Bitwarden CLI
    info "Installing Bitwarden CLI..."
    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || return 1

    # Download and install
    curl -fsSL -o bw.zip "https://github.com/bitwarden/clients/releases/download/cli-v2023.10.0/bw-linux-2023.10.0.zip" 2>/dev/null || {
        warning "Failed to download Bitwarden CLI"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    }

    unzip -o bw.zip 2>/dev/null || {
        warning "Failed to extract Bitwarden CLI"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    }

    # Install to local bin or system bin
    mkdir -p "$HOME/.local/bin"
    mv bw "$HOME/.local/bin/" 2>/dev/null || sudo mv bw /usr/local/bin/

    # Make executable
    chmod +x "$HOME/.local/bin/bw" 2>/dev/null || chmod +x /usr/local/bin/bw

    # Add to PATH if needed
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi

    cd - > /dev/null
    rm -rf "$temp_dir"

    # Verify installation
    if command -v bw &> /dev/null; then
        info "Bitwarden CLI installed successfully"
        return 0
    else
        error "Failed to install Bitwarden CLI"
        return 1
    fi
}

# OAuth2 authentication to get API key from vault
#
# Returns: 0 - Success, 1 - Failed
oauth2_authenticate() {
    info "Authenticating with Vault..."

    # Ensure Bitwarden CLI is available
    if ! command -v bw &> /dev/null; then
        if ! get_vault_cli; then
            error "Failed to get vault CLI"
        fi
    fi

    # Check login status
    local status=$(bw status --raw 2>/dev/null || echo '{"status":"unauthenticated"}')

    if [[ "$status" == *"unauthenticated"* ]]; then
        info "Not logged in to Bitwarden"

        # Try OAuth2 login (requires API key)
        if [[ -n "$BW_CLIENTID" ]] && [[ -n "$BW_CLIENTSECRET" ]]; then
            info "Logging in with OAuth2..."
            bw login --apikey --raw > /dev/null 2>&1 || {
                error "OAuth2 authentication failed. Please set BW_CLIENTID and BW_CLIENTSECRET"
            }
        else
            warning "BW_CLIENTID and BW_CLIENTSECRET not set"
            info "Please login manually: bw login"
            return 1
        fi
    fi

    # Unlock if needed
    if [[ "$status" == *"locked"* ]] || [[ -z "$BW_SESSION" ]]; then
        info "Vault is locked. Unlocking..."
        read -s -p "Enter your Bitwarden password: " BW_PASSWORD
        echo
        export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null) || {
            error "Failed to unlock vault"
        }
        info "Vault unlocked successfully"
    else
        debug "Already authenticated and unlocked"
    fi

    return 0
}

# Clone repo with API key
#
# Args:
#   $1 - GitHub API key (optional, will prompt if not provided)
#
# Returns: 0 - Success
clone_repo_with_api_key() {
    info "Cloning repository..."

    # If ENV_DIR already exists, just verify it's a git repo
    if [[ -d "$ENV_DIR/.git" ]]; then
        debug "Repository already exists"
        return 0
    fi

    # Get GitHub token from Bitwarden or prompt
    local github_token="${GITHUB_SSH_PRIVATE_KEY:-}"

    if [[ -z "$github_token" ]]; then
        if command -v bw &> /dev/null && [[ -n "$BW_SESSION" ]]; then
            github_token=$(bw get password GITHUB_API_KEY 2>/dev/null || echo "")
        fi
    fi

    if [[ -z "$github_token" ]]; then
        warning "GitHub token not found"
        read -p "Enter your GitHub token (or press Enter to use SSH): " github_token
    fi

    # Clone using token or SSH
    if [[ -n "$github_token" ]] && [[ "$github_token" != "ghp_"* ]]; then
        # Use SSH
        debug "Cloning with SSH..."
        git clone git@github.com:doryashar/my_env.git "$ENV_DIR" 2>/dev/null || {
            error "Failed to clone repository"
        }
    else
        # Use HTTPS with token
        debug "Cloning with HTTPS token..."
        git clone "https://${github_token}@github.com/doryashar/my_env.git" "$ENV_DIR" 2>/dev/null || {
            error "Failed to clone repository"
        }
    fi

    info "Repository cloned successfully"
}

# Check if remote is newer
#
# Returns:
#   0 - Remote is up-to-date
#   1 - Remote has updates
check_remote_updates() {
    cd "$ENV_DIR" || return 1

    # Fetch remote changes
    git fetch --quiet 2>/dev/null || return 1

    # Check if we're behind remote
    local local_rev=$(git rev-parse HEAD 2>/dev/null || echo "none")
    local remote_rev=$(git rev-parse @{upstream} 2>/dev/null || echo "none")

    if [[ "$local_rev" != "$remote_rev" ]] && [[ "$remote_rev" != "none" ]]; then
        return 1  # Remote has updates
    fi

    return 0  # Up-to-date
}

# Check if local has changes
#
# Returns:
#   0 - No local changes
#   1 - Local has changes
check_local_changes() {
    cd "$ENV_DIR" || return 1

    if [[ -n "$(git status --porcelain)" ]]; then
        return 1  # Has local changes
    fi

    return 0  # No local changes
}

# Update local repository from remote
#
# Returns: 0 - Success
update_from_remote() {
    info "Updating from remote..."

    cd "$ENV_DIR" || return 1

    # Pull changes
    git pull --ff-only 2>/dev/null || {
        warning "Fast-forward merge failed, trying regular pull..."
        git pull 2>/dev/null || {
            error "Failed to pull changes"
        }
    }

    info "Updated successfully"
}

# Prompt to push local changes
#
# Returns: 0 - Success or declined
prompt_push_changes() {
    warning "You have local changes that are not pushed"

    read -p "Do you want to push your changes? (y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Pushing changes..."
        cd "$ENV_DIR" || return 1

        # Add and commit changes
        git add .
        git commit -m "Auto-sync: $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null || true

        # Push to remote
        git push 2>/dev/null || {
            error "Failed to push changes"
        }

        info "Changes pushed successfully"
    else
        info "Skipping push"
    fi
}

# Main entry point
main() {
    title "** ENV Pre-Run Check **"

    # Check if environment is installed
    if ! is_env_installed; then
        info "Environment not installed. Setting up..."

        # Get vault CLI and authenticate
        if ! get_vault_cli; then
            warning "Failed to get vault CLI, continuing without it..."
        fi

        # Try OAuth2 authentication
        if command -v bw &> /dev/null; then
            oauth2_authenticate || warning "Authentication failed, continuing..."
        fi

        # Clone repo if needed
        if [[ ! -d "$ENV_DIR/.git" ]]; then
            clone_repo_with_api_key
        fi

        # Run setup.sh
        info "Running setup script..."
        if [[ -f "$ENV_DIR/scripts/setup.sh" ]]; then
            bash "$ENV_DIR/scripts/setup.sh"
        else
            error "setup.sh not found at $ENV_DIR/scripts/setup.sh"
        fi

        # Mark as installed
        touch "$ENV_DIR/.env_installed"
        info "Environment installation complete!"
    else
        info "Environment is installed"

        # Check for remote updates
        if check_remote_updates; then
            debug "Remote is up-to-date"
        else
            info "Remote has updates available"
            read -p "Do you want to pull updates? (y/n) " -n 1 -r
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                update_from_remote
            fi
        fi

        # Check for local changes
        if check_local_changes; then
            debug "No local changes"
        else
            prompt_push_changes
        fi
    fi

    title "** Pre-Run complete! **"
}

main "$@"
