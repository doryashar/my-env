#!/bin/bash
# Description: Install Docker on Ubuntu 20.04

# Check if Docker is already installed:
if command -v docker &> /dev/null; then
    echo "Docker is already installed."
    exit 0
fi

# Add Docker's official GPG key:
# First, check if the /etc/apt/keyrings/docker.asc already exists. If it does, we will not download the key again:
if [ -f /etc/apt/keyrings/docker.asc ]; then
    echo "Docker's official GPG key already exists."
else
    sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
fi

# Add the repository to Apt sources:
# First, check if the /etc/apt/sources.list.d/docker.list already exists. If it does, we will not add the repository again:
if [ -f /etc/apt/sources.list.d/docker.list ]; then
    echo "Docker repository already exists."
else
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
fi

# Install Docker Engine:
echo "Installing Docker Engine..."
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin