#!/bin/bash

#########################################################################
# ENV Setup Script
#
# Main environment setup script that configures a complete Linux
# development environment from scratch.
#
# Features:
# - Dotfiles management and synchronization
# - Package installation (APT, PIP, NPM, etc.)
# - Docker and service setup
# - Encrypted secrets management
# - ZSH configuration
# - Cron job setup
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

# Load configuration
if [[ -f "$ENV_DIR/config/repo.conf" ]]; then
    source "$ENV_DIR/config/repo.conf"
fi

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is required but not installed."
    fi
}

validate_commands() {
    # Check required commands
    info "Validating required commands..."
    check_command git
    check_command curl
}

# Generate configuration files
#
# Creates/updates configuration with:
# - Encryption method (age)
# - ENV location
# - Private repo URL
# - Bitwarden email
#
# Returns: 0 - Success
generate_config() {
    info "Generating configuration..."

    # Ensure config directory exists
    mkdir -p "$ENV_DIR/config"

    # Create repo.conf if it doesn't exist
    local config_file="$ENV_DIR/config/repo.conf"
    if [[ ! -f "$config_file" ]]; then
        info "Creating $config_file..."
        cat > "$config_file" << 'EOF'
# Remote git repository URL (optional)
REMOTE_URL="git@github.com:doryashar/my_env"
ENV_DIR="${HOME}/env"

# Bitwarden configuration
export BW_EMAIL="your-email@example.com"

# Private encrypted repository
PRIVATE_URL="git@github.com:doryashar/encrypted"

# Display settings
SHOW_DUFF=off
SHOW_NEOFETCH=on
EOF
        warning "Please edit $config_file and set your BW_EMAIL"
    else
        debug "Configuration file already exists"
    fi

    # Encryption is handled via age (no additional config needed)
    # AGE_SECRET is retrieved from Bitwarden by sync_encrypted.sh
}

# Install Docker and Docker Compose
#
# Returns: 0 - Success
install_docker() {
    info "Setting up Docker..."

    if command -v docker &> /dev/null; then
        debug "Docker already installed"
        return 0
    fi

    # Call the install_docker.sh script if it exists
    if [[ -f "$ENV_DIR/scripts/install_docker.sh" ]]; then
        bash "$ENV_DIR/scripts/install_docker.sh"
    else
        warning "install_docker.sh not found, skipping Docker installation"
    fi
}

# Setup Docker compose services
#
# Returns: 0 - Success
setup_docker_compose() {
    info "Setting up Docker services..."

    # Check if docker compose is available
    if ! command -v docker &> /dev/null; then
        warning "Docker not installed, skipping Docker compose setup"
        return 0
    fi

    # Setup rclone mount if docker compose file exists
    if [[ -f "$ENV_DIR/docker/rclone-mount/docker-compose.yml" ]]; then
        info "Setting up rclone mount service..."
        cd "$ENV_DIR/docker/rclone-mount"
        docker compose up -d 2>/dev/null || warning "Failed to start rclone mount"
    fi

    # Setup ZeroTier if docker compose file exists
    if [[ -f "$ENV_DIR/docker/zerotier/docker-compose.yml" ]]; then
        info "Setting up ZeroTier service..."
        cd "$ENV_DIR/docker/zerotier"
        docker compose up -d 2>/dev/null || warning "Failed to start ZeroTier"
    fi
}

# Install APT packages
#
# Returns: 0 - Success
install_apt_packages() {
    info "Setting up APT packages..."

    # Check if we're on a Debian-based system
    if ! command -v apt-get &> /dev/null; then
        debug "Not a Debian-based system, skipping APT packages"
        return 0
    fi

    # Common packages to install
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
        "exa"
        "unzip"
        "zip"
        "fontconfig"
        "fc-cache"
    )

    # Check which packages are missing
    local missing_packages=()
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg"; then
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

# Install PIP packages
#
# Returns: 0 - Success
install_pip_packages() {
    info "Setting up PIP packages..."

    if ! command -v pip3 &> /dev/null; then
        debug "pip3 not found, skipping PIP packages"
        return 0
    fi

    # Common Python packages
    local packages=(
        "python-lsp-server"
        "black"
        "flake8"
        "pylint"
        "neovim-remote"
    )

    # Install packages
    for pkg in "${packages[@]}"; do
        if ! pip3 show "$pkg" &> /dev/null; then
            info "Installing $pkg..."
            pip3 install --user "$pkg" 2>/dev/null || warning "Failed to install $pkg"
        else
            debug "$pkg already installed"
        fi
    done
}

# Setup cron jobs
#
# Returns: 0 - Success
setup_cron_jobs() {
    info "Setting up cron jobs..."

    # Example cron jobs (customize as needed)
    local cron_file="$ENV_DIR/config/crontab"

    if [[ -f "$cron_file" ]]; then
        # Install custom crontab
        crontab "$cron_file" 2>/dev/null || warning "Failed to install crontab"
    else
        # Create default crontab
        mkdir -p "$ENV_DIR/config"
        cat > "$cron_file" << 'EOF'
# Auto-sync dotfiles daily at 9 AM
0 9 * * * $HOME/env/scripts/sync_env.sh -d -e -l -p > /tmp/env_sync.log 2>&1

# Run backups daily at 2 AM
0 2 * * * $HOME/env/scripts/backup.sh > /tmp/backup.log 2>&1
EOF
        info "Created default crontab at $cron_file"
        info "Edit it and run: crontab $cron_file"
    fi
}

# Extract and setup binaries
#
# Returns: 0 - Success
setup_binaries() {
    info "Setting up binaries..."

    local bin_dir="$ENV_DIR/bin"
    mkdir -p "$bin_dir"

    # Extract appimages if any
    for appimage in "$ENV_DIR"/bin/*.AppImage; do
        if [[ -f "$appimage" ]]; then
            chmod +x "$appimage"
            debug "Made executable: $appimage"
        fi
    done

    # Extract tar.gz binaries in bin directory
    for archive in "$ENV_DIR"/bin/*.tar.gz; do
        if [[ -f "$archive" ]]; then
            info "Extracting $(basename "$archive")..."
            tar -xzf "$archive" -C "$bin_dir" 2>/dev/null || warning "Failed to extract $archive"
        fi
    done

    # Add bin directory to PATH if not already present
    if [[ ":$PATH:" != *":$ENV_DIR/bin:"* ]]; then
        export PATH="$ENV_DIR/bin:$PATH"
        debug "Added $ENV_DIR/bin to PATH"
    fi
}

# Clone GitHub projects
#
# Returns: 0 - Success
clone_github_projects() {
    info "Getting GitHub projects..."

    local projects_dir="$ENV_DIR/tmp/projects"
    mkdir -p "$projects_dir"

    # Define projects to clone (customize as needed)
    local projects=(
        # "doryashar/project1"
        # "doryashar/project2"
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

# Install dotfiles
#
# Returns: 0 - Success
install_dotfiles() {
    info "Setting up Dotfiles..."

    # Run the sync_dotfiles script
    if [[ -f "$ENV_DIR/scripts/sync_dotfiles.sh" ]]; then
        bash "$ENV_DIR/scripts/sync_dotfiles.sh" "$ENV_DIR/config/dotfiles.conf"
    else
        warning "sync_dotfiles.sh not found"
    fi
}

# Setup ZSH
#
# Returns: 0 - Success
setup_zsh() {
    info "Setting up ZSH..."

    # Check if zsh is installed
    if ! command -v zsh &> /dev/null; then
        warning "ZSH not installed, skipping ZSH setup"
        return 0
    fi

    # Install z4h (Zsh for Humans) if not already installed
    if [[ ! -f "$HOME/.z4h.zsh" ]]; then
        info "Installing Zsh for Humans (z4h)..."
        curl -fsSL https://raw.githubusercontent.com/romkatv/zsh4humans/v5/install |
            bash -s -- --yes --skip-x11-checks
    else
        debug "z4h already installed"
    fi

    # Link zsh config files if they exist
    if [[ -f "$ENV_DIR/dotfiles/.zshrc" ]]; then
        ln -sf "$ENV_DIR/dotfiles/.zshrc" "$HOME/.zshrc"
    fi

    if [[ -f "$ENV_DIR/dotfiles/.zshenv" ]]; then
        ln -sf "$ENV_DIR/dotfiles/.zshenv" "$HOME/.zshenv"
    fi

    # Check if zsh is already the default shell
    if [[ "$SHELL" != *"zsh"* ]]; then
        info "Setting ZSH as default shell..."
        chsh -s "$(which zsh)" 2>/dev/null || warning "Failed to set default shell (may require password)"
    fi
}

# Sync encrypted files
#
# Returns: 0 - Success
sync_encrypted_files() {
    info "Syncing encrypted files..."

    if [[ -f "$ENV_DIR/scripts/sync_encrypted.sh" ]]; then
        bash "$ENV_DIR/scripts/sync_encrypted.sh"
    else
        warning "sync_encrypted.sh not found"
    fi
}

# Install fonts
#
# Returns: 0 - Success
install_fonts() {
    info "Installing fonts..."

    if [[ -f "$ENV_DIR/scripts/install_fonts.sh" ]]; then
        bash "$ENV_DIR/scripts/install_fonts.sh"
    else
        warning "install_fonts.sh not found"
    fi
}

# Main setup steps
setup_steps() {
    # Validate required commands
    validate_commands

    # Generate configuration
    generate_config

    # Install system packages
    install_apt_packages
    install_pip_packages

    # Install Docker
    install_docker
    setup_docker_compose

    # Setup binaries
    setup_binaries

    # Sync encrypted files
    sync_encrypted_files

    # Install dotfiles
    install_dotfiles

    # Setup ZSH
    setup_zsh

    # Install fonts
    install_fonts

    # Clone GitHub projects
    clone_github_projects

    # Setup cron jobs
    setup_cron_jobs

    info "Environment setup completed!"
}

main() {
    title "** ENV setup script starting **"

    # Run setup
    setup_steps

    title "** Setup complete! **"
    echo ""
    info "Next steps:"
    echo "  1. Edit $ENV_DIR/config/repo.conf with your settings"
    echo "  2. Run: source $HOME/.zshrc (or restart your shell)"
    echo "  3. Run: $ENV_DIR/scripts/sync_env.sh to sync your files"
}

main "$@"
