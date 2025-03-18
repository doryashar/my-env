#!/bin/bash

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
    if [[ -n "$DEBUG" ]]; then
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

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is required but not installed."
        exit 1
    fi
}

validate_commands() {
    # Check required commands
    check_command git
    check_command curl
    # check_command docker
}

get_bw_password() {
    read -p "Enter your BitWarden password: " BW_PASSWORD
    if [ -z "$BW_PASSWORD" ]; then
        error "GitHub API key is required"
        exit 1
    fi
    export BW_PASSWORD
}

get_secret_keys() {
    export BW_EMAIL="dor.yashar@gmail.com"
    if [ -z "$BW_SESSION" ]; then
        if [ -z "$BW_PASSWORD" ]; then
            get_bw_password
        fi
        bw login --raw 
        export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)
        echo "Logged in successfully!"
    else
        echo "Using existing session."
    fi
    export GITHUB_SSH_PRIVATE_KEY=${GITHUB_SSH_PRIVATE_KEY:-bw get password GITHUB_API_KEY}
    export AGE_SECRET=${AGE_SECRET:-"$(bw get password AGE_SECRET)"}
    if [[ -z "$AGE_SECRET" ]] || [[ -z "$GITHUB_SSH_PRIVATE_KEY" ]]; then
        error "AGE_SECRET/GITHUB_SSH_PRIVATE_KEY is not set. Please set it in your environment."
        exit 1
    fi
}

generate_config() {
    #TODO: implement config generation logic, need to decide:
    # encryption method
    # encryption key
    # ENV location
    # Private Repo URL
    # Dotfiles configuration setup
}

setup_steps() {
    # Validate required commands
    info "Validating required commands..."
    validate_commands

    # Generate config
    info "Generating config..."
    generate_config

    # # Initialize submodules
    # print_message "Initializing submodules..."
    # git submodule init
    # git submodule update

    # Clone public_env repository
    if [ ! -d "~/env" ]; then
        info "Setting up public_env repository..."
        # TODO: Implement decryption mechanism
        # This will be implemented once encryption method is decided
        mkdir -p public_env
        git clone https://github.com/doryashar/my-env ~/env
    fi


    if [ ! -d "~/env/tmp/private_encrypted" ]; then
        # Get secret keys
        info "Getting secret keys..."
        get_secret_keys

        # Clone private_env repository
        info "Setting up private_env repository..."
        if [ ! -d "private" ]; then
            curl -H "Authorization: token $github_api_key" \
                -L https://api.github.com/repos/doryashar/encrypted/tarball \
                -o private_env.tar.gz
            
            mkdir -p private_env
            tar xzf private_env.tar.gz -C private --strip-components=1
            
            # TODO: i might need to do it only after the dotenv sync because .ssh dir is missing
            cd private_env
            git init
            git remote add origin https://github.com/YOUR-USERNAME/YOUR-REPO.git
            git fetch origin main  # Replace "main" with the default branch if different
            git checkout -b main origin/main

            rm private_env.tar.gz
        fi
    fi

    # Docker compose setup
    info "Setting up Docker services..."
    # TODO: Implement Docker compose setup

    # APT packages setup
    info "Setting up APT packages..."
    # TODO: Implement

    # PIP packages setup
    info "Setting up PIP packages..."
    # TODO: Implement
    
    # Cron jobs setup
    info "Setting up cron jobs..."
    # TODO: Implement cron jobs setup

    info "Unzipping binaries..."
    # TODO: Implement

    info "Getting github projects..."
    # TODO: Implement

    info "Setting up Dotfiles..."
    # TODO: Implement

    info "Setting up ZSH..."
    # TODO: Implement
}

main() {    
    title "** ENV setup script starting **"

    # Run setup
    setup_steps

    info "Environment setup completed!"
}

main