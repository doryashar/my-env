#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is required but not installed."
        exit 1
    fi
}

# Check required commands
check_command git
check_command curl
check_command docker

# Get GitHub API key
read -p "Enter your GitHub API key: " github_api_key
if [ -z "$github_api_key" ]; then
    print_error "GitHub API key is required"
    exit 1
fi

# Get decryption password for private repository
read -s -p "Enter decryption password for private repository: " decrypt_password
echo
if [ -z "$decrypt_password" ]; then
    print_error "Decryption password is required"
    exit 1
fi

# Initialize submodules
print_message "Initializing submodules..."
git submodule init
git submodule update

# Clone/update private_env repository
print_message "Setting up private_env repository..."
if [ ! -d "private_env" ]; then
    curl -H "Authorization: token $github_api_key" \
         -L https://api.github.com/repos/yourusername/private_env/tarball \
         -o private_env.tar.gz
    
    mkdir -p private_env
    tar xzf private_env.tar.gz -C private_env --strip-components=1
    rm private_env.tar.gz
fi

# Clone/update and decrypt public_env repository
print_message "Setting up public_env repository..."
if [ ! -d "public_env" ]; then
    curl -H "Authorization: token $github_api_key" \
         -L https://api.github.com/repos/yourusername/public_env/tarball \
         -o public_env.encrypted.tar.gz
    
    # TODO: Implement decryption mechanism
    # This will be implemented once encryption method is decided
    mkdir -p public_env
fi

# Setup steps (to be implemented based on repository contents)
setup_steps() {
    print_message "Setting up environment..."
    
    # Desktop setup
    print_message "Setting up desktop environment..."
    # TODO: Implement desktop setup (conky, shortcuts)
    
    # Dotfiles setup
    print_message "Setting up dotfiles..."
    # TODO: Implement dotfiles setup
    
    # System configuration
    print_message "Setting up system configurations..."
    # TODO: Implement system configs
    
    # Mount NFS
    print_message "Mounting NFS shares..."
    # TODO: Implement NFS mounting
    
    # Setup aliases and scripts
    print_message "Setting up aliases and scripts..."
    # TODO: Implement aliases and scripts setup
    
    # Docker compose setup
    print_message "Setting up Docker services..."
    # TODO: Implement Docker compose setup
    
    # Cron jobs setup
    print_message "Setting up cron jobs..."
    # TODO: Implement cron jobs setup
}

# Run setup
setup_steps

print_success "Environment setup completed!"
print_message "Please log out and log back in for all changes to take effect."