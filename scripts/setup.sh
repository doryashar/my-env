#!/bin/bash

#########################################################################
# ENV Setup Script
#
# One-time setup script for complete Linux development environment.
# Completely independent - does not source any external files.
#
# Can be run directly via curl:
#   curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/setup.sh | bash
#   # Or with custom repo:
#   curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/setup.sh | ENV_URL=https://github.com/user/repo bash
#
# Features:
# - Self-cloning if not running from repo
# - Bitwarden CLI installation and OAuth2 authentication
# - Dependency validation and installation
# - APT/PIP/NPM package installation
# - Docker setup
# - Private encrypted repo creation (if needed)
# - Dotfiles synchronization
# - ZSH (z4h) setup
# - Cron job configuration
#########################################################################

# Colors for early output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default repository URL (can be overridden via ENV_URL)
DEFAULT_REPO_URL="https://github.com/doryashar/my-env.git"

# Check if running from a file (not piped)
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "")"
    SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
    
    # Check if we're running from inside the repo by looking for key files
    if [[ -f "$SCRIPT_DIR/../config/repo.conf" ]] && [[ -f "$SCRIPT_DIR/../functions/common_funcs" ]]; then
        # We're in the repo, set ENV_DIR and continue
        ENV_DIR="$(dirname "$SCRIPT_DIR")"
    else
        # Running from a file but not in repo - need to clone
        NEEDS_CLONE=1
    fi
else
    # Running via curl (piped) - need to clone
    NEEDS_CLONE=1
fi

# If we need to clone the repo first
if [[ "${NEEDS_CLONE:-0}" == "1" ]]; then
    ENV_TARGET="${ENV_DIR:-$HOME/env}"
    REPO_URL="${ENV_URL:-$DEFAULT_REPO_URL}"
    
    echo -e "${BLUE}== ENV Setup ==${NC}"
    echo "Cloning environment repository to $ENV_TARGET..."
    
    if [[ -d "$ENV_TARGET/.git" ]]; then
        echo -e "${GREEN}[INFO]${NC} Repository already exists at $ENV_TARGET"
    else
        if command -v git &>/dev/null; then
            echo -e "${GREEN}[INFO]${NC} Cloning $REPO_URL ..."
            git clone "$REPO_URL" "$ENV_TARGET"
            echo -e "${GREEN}[INFO]${NC} Repository cloned successfully"
        else
            echo -e "${RED}[ERROR]${NC} git is required but not installed."
            echo "Please install git first: sudo apt install git"
            exit 1
        fi
    fi
    
    # Re-run from the cloned repo
    exec bash "$ENV_TARGET/scripts/setup.sh" "$@"
fi

# Now we're running from within the repo
# Enable strict mode after we've handled the cloning logic
set -euo pipefail

# Script directory (we know we're in repo now)
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
ENV_DIR="$(dirname "$SCRIPT_DIR")"

#########################################################################
# Additional Logging Functions
#########################################################################
PURPLE='\033[0;35m'

info() {
    echo -e "${GREEN}[INFO] $*${NC}"
}

debug() {
    if [[ -n "${ENV_DEBUG:-}" ]]; then
        local message="$*"
        message=$(echo "$message" | sed -E 's/(AGE_SECRET|BW_PASSWORD|BW_CLIENTID|BW_CLIENTSECRET|GITHUB_SSH_PRIVATE_KEY|GITHUB_TOKEN|GH_TOKEN|API_KEY|TOKEN|BW_SESSION)=[^ ]+/\1=***HIDDEN***/g')
        echo -e "${PURPLE}[DEBUG] $message${NC}"
    fi
}

warning() {
    echo -e "${YELLOW}[WARNING] $*${NC}"
}

title() {
    echo -e "${BLUE}$*${NC}"
}

error() {
    echo -e "${RED}[ERROR] $*${NC}" >&2
    exit 1
}

# Prompt user for input (works even when piped via curl)
# Usage: prompt "Question? " variable_name
# Usage: prompt_yn "Continue? " && do_something
prompt() {
    local question="$1"
    local var_name="${2:-REPLY}"
    local answer
    
    if [[ -t 0 ]]; then
        read -p "$question" "$var_name"
    else
        echo -n "$question"
        read -r answer < /dev/tty
        eval "$var_name=\$answer"
    fi
}

prompt_yn() {
    local question="$1"
    local reply
    
    if [[ -t 0 ]]; then
        read -p "$question" -n 1 -r
        echo
    else
        echo -n "$question"
        read -r reply < /dev/tty
        REPLY="${reply:0:1}"
    fi
    
    [[ "$REPLY" =~ ^[Yy]$ ]]
}

#########################################################################
# Utility Functions
#########################################################################

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is required but not installed."
    fi
}

command_exists() {
    command -v "$1" > /dev/null 2>&1
}

expand_path() {
    local path="$1"
    echo "${path/#\~/$HOME}"
}

#########################################################################
# Bitwarden Functions
#########################################################################

get_vault_cli() {
    info "Getting Vault CLI (Bitwarden)..."

    if command_exists bw; then
        debug "Bitwarden CLI already installed"
        return 0
    fi

    info "Installing Bitwarden CLI..."
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir" || return 1

    local bw_version="${BW_VERSION:-2024.1.0}"
    debug "Installing Bitwarden CLI version: $bw_version"

    if ! curl -fsSL -o bw.zip "https://github.com/bitwarden/clients/releases/download/cli-v${bw_version}/bw-linux-${bw_version}.zip" 2>/dev/null; then
        warning "Failed to download Bitwarden CLI v${bw_version}"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi

    if ! unzip -o bw.zip 2>/dev/null; then
        warning "Failed to extract Bitwarden CLI"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi

    mkdir -p "$HOME/.local/bin"
    mv bw "$HOME/.local/bin/" 2>/dev/null || sudo mv bw /usr/local/bin/

    chmod +x "$HOME/.local/bin/bw" 2>/dev/null || chmod +x /usr/local/bin/bw

    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi

    cd - > /dev/null
    rm -rf "$temp_dir"

    if command_exists bw; then
        info "Bitwarden CLI installed successfully"
        return 0
    else
        error "Failed to install Bitwarden CLI"
        return 1
    fi
}

oauth2_authenticate() {
    info "Authenticating with Vault..."

    if ! command_exists bw; then
        if ! get_vault_cli; then
            error "Failed to get vault CLI"
        fi
    fi

    local status
    status=$(bw status --raw 2>/dev/null || echo '{"status":"unauthenticated"}')

    if [[ "$status" == *"unauthenticated"* ]]; then
        info "Not logged in to Bitwarden"

        if [[ -n "${BW_CLIENTID:-}" ]] && [[ -n "${BW_CLIENTSECRET:-}" ]]; then
            info "Logging in with OAuth2..."
            if ! bw login --apikey --raw > /dev/null 2>&1; then
                error "OAuth2 authentication failed. Please set BW_CLIENTID and BW_CLIENTSECRET"
            fi
        else
            warning "BW_CLIENTID and BW_CLIENTSECRET not set"
            info "Please login manually: bw login"
            return 1
        fi
    fi

    if [[ "$status" == *"locked"* ]] || [[ -z "${BW_SESSION:-}" ]]; then
        info "Vault is locked. Unlocking..."
        local bw_password
        if [[ -t 0 ]]; then
            read -s -p "Enter your Bitwarden password: " bw_password
        else
            echo -n "Enter your Bitwarden password: "
            read -s bw_password < /dev/tty
        fi
        echo
        export BW_SESSION=$(bw unlock --passwordfile <(echo "$bw_password") --raw 2>/dev/null) || {
            error "Failed to unlock vault"
        }
        info "Vault unlocked successfully"
    else
        debug "Already authenticated and unlocked"
    fi

    return 0
}

#########################################################################
# Repository Functions
#########################################################################

clone_public_repo() {
    info "Cloning public repository..."

    if [[ -d "$ENV_DIR/.git" ]]; then
        debug "Repository already exists at $ENV_DIR"
        return 0
    fi

    # Get URL from config or use default
    local public_url="${REMOTE_URL:-}"
    if [[ -z "$public_url" ]]; then
        # Try to get from git remote if we're somehow running from within a git repo
        public_url="$(git -C "$ENV_DIR" remote get-url origin 2>/dev/null || echo "")"
    fi
    if [[ -z "$public_url" ]]; then
        # Fallback to default
        public_url="git@github.com:doryashar/my-env.git"
        warning "No REMOTE_URL configured, using default: $public_url"
    fi

    local github_token="${GITHUB_TOKEN:-}"

    if [[ -z "$github_token" ]] && command_exists bw && [[ -n "${BW_SESSION:-}" ]]; then
        github_token=$(bw get password GITHUB_API_KEY 2>/dev/null || echo "")
    fi

    if [[ -n "$github_token" ]] && [[ "$public_url" == *"github.com"* ]]; then
        debug "Cloning with HTTPS token..."
        local https_url
        https_url=$(echo "$public_url" | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||')
        git clone "https://${github_token}@${https_url#https://}" "$ENV_DIR" 2>/dev/null || {
            warning "HTTPS clone failed, trying SSH..."
            git clone "$public_url" "$ENV_DIR" 2>/dev/null || error "Failed to clone repository"
        }
    else
        debug "Cloning with SSH..."
        git clone "$public_url" "$ENV_DIR" 2>/dev/null || error "Failed to clone repository"
    fi

    info "Repository cloned successfully"
}

check_remote_repo_exists() {
    local repo_url="$1"

    if [[ "$repo_url" =~ git@github\.com:([^/]+)/(.+)\.git ]]; then
        local owner="${BASH_REMATCH[1]}"
        local repo_name="${BASH_REMATCH[2]}"
    elif [[ "$repo_url" =~ github\.com/([^/]+)/(.+)(\.git)? ]]; then
        local owner="${BASH_REMATCH[1]}"
        local repo_name="${BASH_REMATCH[2]%.git}"
    else
        warning "Could not parse repository URL: $repo_url"
        return 1
    fi

    debug "Checking if repo exists: $owner/$repo_name"

    if git ls-remote "$repo_url" HEAD &>/dev/null; then
        return 0
    else
        return 1
    fi
}

create_private_repo() {
    local repo_url="$1"
    local repo_name=""
    local owner=""

    if [[ "$repo_url" =~ git@github\.com:([^/]+)/(.+)\.git ]]; then
        owner="${BASH_REMATCH[1]}"
        repo_name="${BASH_REMATCH[2]}"
    elif [[ "$repo_url" =~ github\.com/([^/]+)/(.+)(\.git)? ]]; then
        owner="${BASH_REMATCH[1]}"
        repo_name="${BASH_REMATCH[2]%.git}"
    else
        error "Could not parse repository URL: $repo_url"
        return 1
    fi

    info "Creating private repository: $owner/$repo_name"

    if command_exists gh; then
        if gh repo create "$owner/$repo_name" --private 2>/dev/null; then
            info "Repository created successfully!"
            return 0
        else
            warning "GitHub CLI failed. Trying manual creation..."
        fi
    fi

    local github_token="${GITHUB_TOKEN:-}"

    if [[ -z "$github_token" ]] && command_exists bw && [[ -n "${BW_SESSION:-}" ]]; then
        github_token=$(bw get password GITHUB_API_KEY 2>/dev/null || echo "")
    fi

    if [[ -z "$github_token" ]]; then
        info "GitHub CLI not available or failed."
        prompt "Enter your GitHub Personal Access Token (with repo scope): " github_token
    fi

    if [[ -n "$github_token" ]]; then
        local api_url="https://api.github.com/user/repos"
        local response
        response=$(curl -s -X POST \
            -H "Authorization: token $github_token" \
            -H "Accept: application/vnd.github.v3+json" \
            -d "{\"name\":\"$repo_name\",\"private\":true}" \
            "$api_url")

        if echo "$response" | jq -e '.clone_url' >/dev/null 2>&1; then
            info "Repository created successfully via API!"
            return 0
        else
            error "Failed to create repository via GitHub API"
            echo "Response: $response"
            return 1
        fi
    fi

    warning "Could not auto-create repository. Please create it manually:"
    echo ""
    echo "1. Visit: https://github.com/new"
    echo "2. Repository name: $repo_name"
    echo "3. Set to **Private**"
    echo "4. Click 'Create repository'"
    echo "5. Run: $ENV_DIR/scripts/sync_encrypted.sh"
    echo ""
    return 1
}

sync_encrypted_files() {
    info "Syncing encrypted files..."

    if [[ ! -f "$ENV_DIR/scripts/sync_encrypted.sh" ]]; then
        warning "sync_encrypted.sh not found"
        return 0
    fi

    local private_url=""
    if [[ -f "$ENV_DIR/config/repo.conf" ]]; then
        source "$ENV_DIR/config/repo.conf"
        private_url="$PRIVATE_URL"
    fi

    if [[ -z "$private_url" ]]; then
        warning "PRIVATE_URL not set in config/repo.conf"
        return 0
    fi

    info "Checking if private repository exists..."
    if check_remote_repo_exists "$private_url"; then
        debug "Private repository exists, syncing..."
        bash "$ENV_DIR/scripts/sync_encrypted.sh" || warning "Encrypted sync failed (non-fatal)"
    else
        warning "Private repository does not exist: $private_url"
        echo ""
        echo "Would you like to create a new private repository for encrypted files?"
        if prompt_yn "Create repository? (y/n) "; then
            if create_private_repo "$private_url"; then
                bash "$ENV_DIR/scripts/sync_encrypted.sh" || warning "Encrypted sync failed (non-fatal)"
            fi
        else
            info "Skipping encrypted files sync. You can create it later:"
            echo "  1. Create a private repo on GitHub"
            echo "  2. Update PRIVATE_URL in $ENV_DIR/config/repo.conf"
            echo "  3. Run: $ENV_DIR/scripts/sync_encrypted.sh"
        fi
    fi
}

#########################################################################
# Setup Functions
#########################################################################

validate_commands() {
    info "Validating required commands..."
    check_command git
    check_command curl
}

generate_config() {
    info "Generating configuration..."

    mkdir -p "$ENV_DIR/config"

    local config_file="$ENV_DIR/config/repo.conf"
    if [[ ! -f "$config_file" ]]; then
        info "Creating $config_file..."
        cat > "$config_file" << 'EOF'
# Remote git repository URL (optional)
REMOTE_URL="git@github.com:doryashar/my-env"
ENV_DIR="${HOME}/env"

# Bitwarden configuration
export BW_EMAIL="your-email@example.com"

# Private encrypted repository
PRIVATE_URL="git@github.com:doryashar/encrypted.git"

# Display settings
SHOW_DUFF=off
SHOW_NEOFETCH=on

# Sync timing (days)
CHECK_INTERVAL_DAYS="${CHECK_INTERVAL_DAYS:-1}"
SYNC_INTERVAL_DAYS="${SYNC_INTERVAL_DAYS:-7}"

# Merge conflict resolution strategy: ask, local, remote, rename, ignore
DEFAULT_CONFLICT_STRATEGY="${DEFAULT_CONFLICT_STRATEGY:-ask}"
EOF
        warning "Please edit $config_file and set your BW_EMAIL"
    else
        debug "Configuration file already exists"
    fi
}

install_docker() {
    info "Setting up Docker..."

    if command_exists docker; then
        debug "Docker already installed"
        return 0
    fi

    if [[ -f "$ENV_DIR/scripts/install_docker.sh" ]]; then
        bash "$ENV_DIR/scripts/install_docker.sh" || warning "Docker installation failed (non-fatal)"
    else
        warning "install_docker.sh not found, skipping Docker installation"
    fi
}

setup_docker_compose() {
    info "Setting up Docker services..."

    if ! command_exists docker; then
        warning "Docker not installed, skipping Docker compose setup"
        return 0
    fi

    if [[ -f "$ENV_DIR/docker/rclone-mount/docker-compose.yml" ]]; then
        info "Setting up rclone mount service..."
        (cd "$ENV_DIR/docker/rclone-mount" && docker compose up -d 2>/dev/null) || warning "Failed to start rclone mount"
    fi

    if [[ -f "$ENV_DIR/docker/zerotier/docker-compose.yml" ]]; then
        info "Setting up ZeroTier service..."
        (cd "$ENV_DIR/docker/zerotier" && docker compose up -d 2>/dev/null) || warning "Failed to start ZeroTier"
    fi
}

install_apt_packages() {
    info "Setting up APT packages..."

    if ! command_exists apt-get; then
        debug "Not a Debian-based system, skipping APT packages"
        return 0
    fi

    local packages=(
        "build-essential"
        "vim"
        "neovim"
        "tmux"
        "zsh"
        "git"
        "curl"
        "wget"
        "htop"
        "tree"
        "ripgrep"
        "fd-find"
        "bat"
        "eza"
        "jq"
        "unzip"
        "zip"
        "fontconfig"
    )

    local missing_packages=()
    for pkg in "${packages[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        info "Installing missing packages: ${missing_packages[*]}"
        sudo apt-get update -qq
        sudo apt-get install -y "${missing_packages[@]}"
    else
        debug "All APT packages already installed"
    fi
}

install_pip_packages() {
    info "Setting up PIP packages..."

    if ! command_exists pip3; then
        debug "pip3 not found, skipping PIP packages"
        return 0
    fi

    local packages=(
        "python-lsp-server"
        "black"
        "flake8"
        "pylint"
        "neovim-remote"
    )

    for pkg in "${packages[@]}"; do
        if ! pip3 show "$pkg" &> /dev/null; then
            info "Installing $pkg..."
            pip3 install --user "$pkg" 2>/dev/null || warning "Failed to install $pkg"
        else
            debug "$pkg already installed"
        fi
    done
}

setup_cron_jobs() {
    info "Setting up cron jobs..."

    local cron_file="$ENV_DIR/config/crontab"

    if [[ -f "$cron_file" ]]; then
        crontab "$cron_file" 2>/dev/null || warning "Failed to install crontab"
    else
        mkdir -p "$ENV_DIR/config"
        cat > "$cron_file" << 'EOF'
# Auto-sync dotfiles daily at 9 AM
0 9 * * * $HOME/env/scripts/sync_env.sh --sync > /tmp/env_sync.log 2>&1

# Run backups daily at 2 AM
0 2 * * * $HOME/env/scripts/backup.sh > /tmp/backup.log 2>&1
EOF
        info "Created default crontab at $cron_file"
        info "Edit it and run: crontab $cron_file"
    fi
}

setup_binaries() {
    info "Setting up binaries..."

    local bin_dir="$ENV_DIR/bin"
    mkdir -p "$bin_dir"

    for appimage in "$ENV_DIR"/bin/*.AppImage; do
        if [[ -f "$appimage" ]]; then
            chmod +x "$appimage"
            debug "Made executable: $appimage"
        fi
    done

    for archive in "$ENV_DIR"/bin/*.tar.gz; do
        if [[ -f "$archive" ]]; then
            info "Extracting $(basename "$archive")..."
            tar -xzf "$archive" -C "$bin_dir" 2>/dev/null || warning "Failed to extract $archive"
        fi
    done

    if [[ ":$PATH:" != *":$ENV_DIR/bin:"* ]]; then
        export PATH="$ENV_DIR/bin:$PATH"
        debug "Added $ENV_DIR/bin to PATH"
    fi
}

clone_github_projects() {
    info "Getting GitHub projects..."

    local projects_dir="$ENV_DIR/tmp/projects"
    mkdir -p "$projects_dir"

    local projects=(
    )

    for project in "${projects[@]}"; do
        local repo_name="${project##*/}"
        if [[ ! -d "$projects_dir/$repo_name" ]]; then
            info "Cloning $project..."
            git clone "git@github.com:$project.git" "$projects_dir/$repo_name" 2>/dev/null || warning "Failed to clone $project"
        else
            debug "$repo_name already exists"
        fi
    done
}

install_dotfiles() {
    info "Setting up Dotfiles..."

    if [[ -f "$ENV_DIR/scripts/sync_dotfiles.sh" ]]; then
        bash "$ENV_DIR/scripts/sync_dotfiles.sh" "$ENV_DIR/config/dotfiles.conf" || warning "Dotfiles sync failed (non-fatal)"
    else
        warning "sync_dotfiles.sh not found"
    fi
}

setup_zsh() {
    info "Setting up ZSH..."

    if ! command_exists zsh; then
        warning "ZSH not installed, skipping ZSH setup"
        return 0
    fi

    if [[ ! -f "$HOME/.z4h.zsh" ]]; then
        if [[ -t 0 ]]; then
            info "Installing Zsh for Humans (z4h)..."
            curl -fsSL https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install |
                bash -s -- --yes --skip-x11-checks
        else
            warning "No TTY detected, skipping z4h installation (non-interactive environment)"
            debug "z4h will be installed when you run setup in an interactive shell"
        fi
    else
        debug "z4h already installed"
    fi

    if [[ -f "$ENV_DIR/dotfiles/.zshrc" ]]; then
        ln -sf "$ENV_DIR/dotfiles/.zshrc" "$HOME/.zshrc"
    fi

    if [[ -f "$ENV_DIR/dotfiles/.zshenv" ]]; then
        ln -sf "$ENV_DIR/dotfiles/.zshenv" "$HOME/.zshenv"
    fi

    if [[ "$SHELL" != *"zsh"* ]]; then
        info "Setting ZSH as default shell..."
        chsh -s "$(which zsh)" 2>/dev/null || warning "Failed to set default shell (may require password)"
    fi
}

install_fonts() {
    info "Installing fonts..."

    if [[ -f "$ENV_DIR/scripts/install_fonts.sh" ]]; then
        bash "$ENV_DIR/scripts/install_fonts.sh" || warning "Font installation failed (non-fatal)"
    else
        warning "install_fonts.sh not found"
    fi
}

#########################################################################
# Main Setup
#########################################################################

setup_steps() {
    validate_commands

    generate_config

    install_apt_packages
    install_pip_packages

    install_docker
    setup_docker_compose

    setup_binaries

    sync_encrypted_files

    install_dotfiles

    setup_zsh

    install_fonts

    clone_github_projects

    setup_cron_jobs

    info "Environment setup completed!"
}

is_env_installed() {
    if [[ ! -d "$ENV_DIR" ]]; then
        return 1
    fi

    local marker_file="$ENV_DIR/.env_installed"
    if [[ ! -f "$marker_file" ]]; then
        return 1
    fi

    return 0
}

main() {
    title "** ENV Setup Script **"

    if ! is_env_installed; then
        info "Environment not installed. Setting up..."

        if ! get_vault_cli; then
            warning "Failed to get vault CLI, continuing without it..."
        fi

        if command_exists bw; then
            oauth2_authenticate || warning "Authentication failed, continuing..."
        fi

        if [[ ! -d "$ENV_DIR/.git" ]]; then
            clone_public_repo
        fi

        setup_steps

        touch "$ENV_DIR/.env_installed"
        info "Environment installation complete!"
    else
        info "Environment is installed. Running setup steps..."

        setup_steps
    fi

    title "** Setup complete! **"
    echo ""
    info "Next steps:"
    echo "  1. Edit $ENV_DIR/config/repo.conf with your settings"
    echo "  2. Run: source $HOME/.zshrc (or restart your shell)"
    echo "  3. Run: $ENV_DIR/scripts/sync_env.sh --sync to sync your files"
}

main "$@"
