#!/bin/bash

# Install required packages
sudo apt update
sudo apt install -y sshfs

# Create mount point if it doesn't exist
mkdir -p ~/Desktop

# Generate SSH key if needed
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

# Create credentials directory with restricted permissions
sudo mkdir -p /etc/sshfs
sudo chmod 700 /etc/sshfs

# Create password file (if not using key-based auth)
sudo tee /etc/sshfs/sftp_password << EOF
your_password_here
EOF
sudo chmod 600 /etc/sshfs/sftp_password

# Add fstab entry (create backup first)
sudo cp /etc/fstab /etc/fstab.backup

# Add the mount to fstab (choose one of these options):

# Option 1: Using password authentication
sudo tee -a /etc/fstab << EOF
sshfs#username@server:/remote/path /home/username/Desktop fuse defaults,_netdev,user,idmap=user,transform_symlinks,identityfile=/home/username/.ssh/id_rsa,allow_other,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,password_stdin 0 0
EOF

# Option 2: Using key-based authentication (recommended)
sudo tee -a /etc/fstab << EOF
sshfs#username@server:/remote/path /home/username/Desktop fuse defaults,_netdev,user,idmap=user,transform_symlinks,identityfile=/home/username/.ssh/id_rsa,allow_other,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 0 0
EOF

# Test mount
sudo mount -a
