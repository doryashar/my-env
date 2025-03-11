## TODO:
   - Simple command to run `prerun.sh`:
   - `prerun.sh` will check if env is installed. 
      - if not:
         - get a valut cli
         - run OAUTH2 authentication to get API key from the vault
         - clone the repo with the the API key
         - run `setup.sh`
      - if yes:
         - check if the remote is newer, if so update the local repo
         - check if local has changes. if so, ask the user to push the changes
   
   - `setup.sh` will:
      - setup dotfiles (including local, config, zsh, tmux, zellij, alacritty, conky etc)
      - install packages (apt, snap, flatpak, brew, pip, npm, rustup, go, etc)
      - setup services (backup)
      - setup docker with the containers (zerotier, rclone)
      - setup cron jobs
      - setup z4h, zellij as default shell
      - register with uptimekuma
      - show screen with: IP, hostname, uptimekuma, Memory/CPU/Disk/Network Usage, tasks, calendar, weather.

# My Environment Setup

This repository contains my essential Linux environment configuration, contains submodule:

- `private` (Private & Encrypted Repository): Contains sensitive data and configurations

## Prerequisites

- Git
- GitHub API Key with appropriate permissions
- Linux-based system
- NFS server configuration (for mounting)
- Docker (for running containerized services)

## Setup

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/my_env.git ~/env
   cd ~/env
   ```

2. Run the setup script:
   ```bash
   ./setup.sh
   ```

   You will be prompted for:
   - GitHub API Key (for accessing repositories)
   - Decryption password (for private repository)

## What Gets Set Up

The setup script will configure:

- Desktop environment
  - Desktop shortcuts
  - Conky configuration
- Dotfiles (.bashrc, .vimrc, etc.)
- System configurations
- Password management
- Standalone binaries
- NFS mounts
- Custom aliases and scripts
- Docker compose configurations
- Automated tasks (cron jobs)
  - Daily backups
  - Other scheduled tasks

## Repository Structure

```
my_env/
├── private/        # Private encrypted submodule (sensitive data)
├── runme.sh        # Main setup script
└── README.md       # This documentation
```

## Security

- The `private` repository is encrypted to protect sensitive information
- Decryption key is required during setup
- Never commit unencrypted sensitive data

## Maintenance

To update your environment:

1. Pull the latest changes:
   ```bash
   git pull
   git submodule update --remote
   ```

2. Run the setup script again:
   ```bash
   ./runme.sh
   ```

## Contributing

This is a personal environment setup repository. While you're welcome to fork and modify it for your own use, pull requests are not accepted.

## License

This project is licensed under the MIT License - see the LICENSE file for details.