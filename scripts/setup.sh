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
        mkdir -p ~/env
        git clone git@github.com:doryashar/my-env ~/env
    fi


    if [ ! -d "~/env/tmp/private_encrypted" ]; then
        #TODO: run sync_encrypted or sync_env
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