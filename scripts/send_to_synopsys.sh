#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 <file1> [file2] [file3] ..."
    echo "Environment variables:"
    echo "  SFTP_USER: SFTP username"
    echo "  SFTP_PASS: SFTP password"
    echo "  SFTP_HOST: SFTP host"
    echo "  SFTP_PORT: SFTP port (optional, default: 22)"
    exit 1
}

# Check if at least one file argument is provided
if [ $# -eq 0 ]; then
    echo "Error: Please provide at least one file or directory path as an argument."
    usage
fi

# Create a temporary directory
temp_dir=$(mktemp -d)
echo "Created temporary directory: $temp_dir"

# Create a temporary file for SFTP commands
sftp_commands=$(mktemp)

# Process each file/directory argument
for path in "$@"; do
    # Check if the path exists
    if [ ! -e "$path" ]; then
        echo "Error: The specified path does not exist: $path"
        continue
    fi

    # Get the basename of the path
    basename=$(basename "$path")

    # Create the compressed file
    compressed_file="$temp_dir/${basename}.tar.gz"
    tar -czf "$compressed_file" -C "$(dirname "$path")" "$basename"
    echo "Created compressed file: $compressed_file"

    # Add the put command to the SFTP commands file
    echo "put $compressed_file /Incoming/${basename}.tar.gz" >> "$sftp_commands"
done

# Get SFTP credentials from environment variables
sftp_user=${SFTP_USER:-}
sftp_pass=${SFTP_PASS:-}
sftp_host=${SFTP_HOST:-eft.synopsys.com}
sftp_port=${SFTP_PORT:-22}
sftp_key=${SFTP_KEY:-}

if [ -z "$sftp_user" ] || [ -z "$sftp_pass" ] || [ -z "$sftp_host" ]; then
    echo "Error: SFTP credentials are not set in environment variables."
    echo "you can set SFTP_USER, SFTP_PASS, and SFTP_HOST."
fi

# Check if SFTP credentials are set
if [ -z "$sftp_host" ]; then
    read -p "Enter host: " sftp_host
fi
if [ -z "$sftp_user" ]; then
    read -p "Enter user: " sftp_user
fi
if [ -z "$sftp_pass" ]; then
    read -p "Enter password: " sftp_pass
fi

# Function to use expect for SFTP transfer
use_expect() {
    expect << EOF
spawn sftp -P $sftp_port $sftp_user@$sftp_host
expect "password:"
send "$sftp_pass\r"
expect "sftp>"
send "$(cat $sftp_commands)\r"
expect "sftp>"
send "bye\r"
expect eof
EOF
}

# Function to use key-based authentication for SFTP transfer
use_key_auth() {
    sftp -P "$sftp_port" -i "$sftp_key" -b "$sftp_commands" "$sftp_user@$sftp_host"
}

# Connect to SFTP and send the files
echo "Connecting to SFTP and sending file(s)..."
if command -v expect &> /dev/null && [ -n "$sftp_pass" ]; then
    use_expect
elif [ -n "$sftp_key" ]; then
    use_key_auth
else
    echo "Error: Neither 'expect' command nor SSH key is available for authentication."
    echo "Please provide either SFTP_PASS or SFTP_KEY."
    exit 1
fi

# # Connect to SFTP and send the files
# echo "Connecting to SFTP and sending file(s)..."
# sshpass -p "$sftp_pass" sftp -P "$sftp_port" -b "$sftp_commands" "$sftp_user@$sftp_host"

# Check if the SFTP transfer was successful
if [ $? -eq 0 ]; then
    echo "File(s) transferred successfully via SFTP."
else
    echo "Error: Failed to transfer file(s) via SFTP."
fi

# Cleanup
echo "Cleaning up..."
rm -rf "$temp_dir"
rm "$sftp_commands"
echo "Cleanup completed."

echo "Script execution finished. please check your mail"
