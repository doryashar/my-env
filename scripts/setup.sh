#!/bin/bash

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is required but not installed."
        exit 1
    fi
}

validate_commands() {
    # Check required commands
    check_command git
    check_command curl
    # check_command docker
}

get_secret_keys() {
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
}
generate_config() {
    #TODO: implement config generation logic, need to decide:
    # encryption method
    # encryption key
    # ENV location
    # Private Repo URL
    # Dotfiles configuration setup
}

main() {
    title "** ENV setup script starting **"

    # Validate required commands
    title "Validating required commands..."
    validate_commands

    # Generate config
    title "Generating config..."
    generate_config

    # Get secret keys
    title "Getting secret keys..."
    get_secret_keys

    # # Initialize submodules
    # print_message "Initializing submodules..."
    # git submodule init
    # git submodule update

    # Clone public_env repository
    title "Setting up public_env repository..."
    if [ ! -d "env" ]; then
        # TODO: Implement decryption mechanism
        # This will be implemented once encryption method is decided
        mkdir -p public_env
        curl -H "Authorization: token $github_api_key" \
            -L https://api.github.com/repos/yourusername/public_env/tarball \
            -o public_env.encrypted.tar.gz
    fi

    # Clone private_env repository
    title "Setting up private_env repository..."
    if [ ! -d "private" ]; then
        curl -H "Authorization: token $github_api_key" \
            -L https://api.github.com/repos/doryashar/encrypted/tarball \
            -o private_env.tar.gz
        
        mkdir -p private_env
        tar xzf private_env.tar.gz -C private --strip-components=1
        rm private_env.tar.gz
    fi

}
    

# Setup steps (to be implemented based on repository contents)
setup_steps() {
    
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