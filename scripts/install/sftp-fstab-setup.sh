#!/bin/bash
set -euo pipefail

sudo apt update
sudo apt install -y sshfs

mkdir -p ~/Desktop

if [[ ! -f ~/.ssh/id_rsa ]]; then
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

sudo mkdir -p /etc/sshfs
sudo chmod 700 /etc/sshfs

read -p "Enter SFTP password: " -s SFTP_PASSWORD
echo
sudo tee /etc/sshfs/sftp_password > /dev/null << EOF
${SFTP_PASSWORD}
EOF
sudo chmod 600 /etc/sshfs/sftp_password

sudo cp /etc/fstab /etc/fstab.backup

read -p "Enter SFTP user@host (e.g. user@server): " SFTP_ENDPOINT
read -p "Enter remote path (e.g. /remote/path): " REMOTE_PATH
LOCAL_MOUNT="/home/$(whoami)/Desktop"
SSH_KEY="/home/$(whoami)/.ssh/id_rsa"

grep -q "$LOCAL_MOUNT" /etc/fstab && {
  echo "fstab entry for $LOCAL_MOUNT already exists, skipping"
  exit 0
}

sudo tee -a /etc/fstab > /dev/null << EOF
sshfs#${SFTP_ENDPOINT}:${REMOTE_PATH} ${LOCAL_MOUNT} fuse defaults,_netdev,user,idmap=user,transform_symlinks,identityfile=${SSH_KEY},allow_other,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 0 0
EOF

sudo mount -a
