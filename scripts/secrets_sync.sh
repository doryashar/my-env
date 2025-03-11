#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories to use
SSH_DIR="$HOME/.ssh"
SECRETS_FILE="$HOME/.secrets"
PRIVATE_DIR="$HOME/private"

# Ensure directories exist
mkdir -p "$SSH_DIR"
mkdir -p "$PRIVATE_DIR"

# Function to check if Bitwarden is logged in
check_bw_status() {
    local status
    status=$(bw status | jq -r '.status')
    
    if [ "$status" = "unauthenticated" ]; then
        echo -e "${RED}You are not logged in to Bitwarden.${NC}"
        echo -e "${YELLOW}Please log in using 'bw login' or 'bw unlock' first.${NC}"
        exit 1
    elif [ "$status" = "locked" ]; then
        echo -e "${YELLOW}Your Bitwarden vault is locked.${NC}"
        echo -e "${YELLOW}Please unlock it using 'bw unlock' first.${NC}"
        exit 1
    fi
}

# Function to sync SSH keys from Bitwarden to local
sync_ssh_keys_from_bitwarden() {
    echo -e "${BLUE}Syncing SSH keys from Bitwarden to local...${NC}"
    
    # Get items from Bitwarden with folder "SSH Keys" or items with "ssh" in the name
    local ssh_items
    ssh_items=$(bw list items --search "ssh" | jq -c '.[] | select(.name | test("ssh|SSH|key|Key"; "i"))')
    
    if [ -z "$ssh_items" ]; then
        echo -e "${YELLOW}No SSH keys found in Bitwarden.${NC}"
        return
    fi
    
    echo "$ssh_items" | while read -r item; do
        local name
        local notes
        local filename
        
        name=$(echo "$item" | jq -r '.name')
        notes=$(echo "$item" | jq -r '.notes')
        
        # Skip if notes are empty
        if [ -z "$notes" ] || [ "$notes" = "null" ]; then
            continue
        fi
        
        # Determine filename from name
        filename=$(echo "$name" | sed 's/ /_/g' | tr '[:upper:]' '[:lower:]')
        
        # Check if filename needs extension
        if [[ ! "$filename" =~ \.pub$ && ! "$filename" =~ id_ ]]; then
            if [[ "$notes" == *"PRIVATE KEY"* ]]; then
                filename="id_${filename}"
            elif [[ "$notes" == *"PUBLIC KEY"* ]]; then
                filename="${filename}.pub"
            fi
        fi
        
        # Check if file already exists
        if [ ! -f "$SSH_DIR/$filename" ]; then
            echo -e "  ${GREEN}Writing SSH key: $filename${NC}"
            echo "$notes" > "$SSH_DIR/$filename"
            
            # Set proper permissions
            if [[ ! "$filename" =~ \.pub$ ]]; then
                chmod 600 "$SSH_DIR/$filename"
            else
                chmod 644 "$SSH_DIR/$filename"
            fi
        else
            echo -e "  ${YELLOW}SSH key already exists: $filename${NC}"
        fi
    done
}

# Function to sync SSH keys from local to Bitwarden
sync_ssh_keys_to_bitwarden() {
    echo -e "${BLUE}Syncing SSH keys from local to Bitwarden...${NC}"
    
    # Get existing SSH key items from Bitwarden
    local existing_keys
    existing_keys=$(bw list items --search "ssh" | jq -c '.[] | select(.name | test("ssh|SSH|key|Key"; "i")) | .name')
    
    # Find SSH keys in the SSH_DIR
    find "$SSH_DIR" -type f -not -path "*/\.*" | while read -r file; do
        local filename
        local content
        local key_type
        
        filename=$(basename "$file")
        
        # Skip known_hosts, config, authorized_keys, and other non-key files
        if [[ "$filename" == "known_hosts" || "$filename" == "config" || "$filename" == "authorized_keys" || "$filename" == "environment" ]]; then
            continue
        fi
        
        content=$(cat "$file")
        
        # Determine key type
        if [[ "$filename" =~ \.pub$ ]]; then
            key_type="Public SSH Key"
        else
            key_type="Private SSH Key"
        fi
        
        # Check if key already exists in Bitwarden
        if echo "$existing_keys" | grep -q "\"$filename\"" || echo "$existing_keys" | grep -q "\"$key_type: $filename\""; then
            echo -e "  ${YELLOW}SSH key already exists in Bitwarden: $filename${NC}"
        else
            echo -e "  ${GREEN}Adding SSH key to Bitwarden: $filename${NC}"
            
            # Create JSON for new item
            local item_json
            item_json=$(jq -n \
                --arg name "$key_type: $filename" \
                --arg notes "$content" \
                '{name: $name, notes: $notes, type: 2, secureNote: {type: 0}}')
            
            # Add item to Bitwarden
            echo "$item_json" | bw encode | bw create item > /dev/null
        fi
    done
}

# Function to sync secrets from Bitwarden to local
sync_secrets_from_bitwarden() {
    echo -e "${BLUE}Syncing secrets from Bitwarden to local...${NC}"
    
    # Get item from Bitwarden with name "secrets" or ".secrets" - using simple grep
    local secret_item
    secret_item=$(bw list items | jq -c '.[] | select(.name == "secrets" or .name == ".secrets")')
    
    if [ -z "$secret_item" ]; then
        echo -e "${YELLOW}No secrets file found in Bitwarden.${NC}"
        return
    fi
    
    local notes
    notes=$(echo "$secret_item" | jq -r '.notes')
    
    # Skip if notes are empty
    if [ -z "$notes" ] || [ "$notes" = "null" ]; then
        echo -e "${YELLOW}Secrets file in Bitwarden is empty.${NC}"
        return
    fi
    
    # Check if file already exists and compare content
    if [ -f "$SECRETS_FILE" ]; then
        local local_content
        local_content=$(cat "$SECRETS_FILE")
        
        if [ "$local_content" = "$notes" ]; then
            echo -e "${YELLOW}Secrets file is already up to date.${NC}"
        else
            echo -e "${GREEN}Updating secrets file from Bitwarden.${NC}"
            echo "$notes" > "$SECRETS_FILE"
            chmod 600 "$SECRETS_FILE"
        fi
    else
        echo -e "${GREEN}Creating secrets file from Bitwarden.${NC}"
        echo "$notes" > "$SECRETS_FILE"
        chmod 600 "$SECRETS_FILE"
    fi
}

# Function to sync secrets from local to Bitwarden
sync_secrets_to_bitwarden() {
    echo -e "${BLUE}Syncing secrets from local to Bitwarden...${NC}"
    
    if [ ! -f "$SECRETS_FILE" ]; then
        echo -e "${YELLOW}Local secrets file does not exist.${NC}"
        return
    fi
    
    local content
    content=$(cat "$SECRETS_FILE")
    
    # Get existing secrets item from Bitwarden - using simple condition
    local existing_item
    existing_item=$(bw list items | jq -c '.[] | select(.name == "secrets" or .name == ".secrets")')
    
    if [ -z "$existing_item" ]; then
        echo -e "${GREEN}Adding secrets file to Bitwarden.${NC}"
        
        # Create JSON for new item
        local item_json
        item_json=$(jq -n \
            --arg name ".secrets" \
            --arg notes "$content" \
            '{name: $name, notes: $notes, type: 2, secureNote: {type: 0}}')
        
        # Add item to Bitwarden
        echo "$item_json" | bw encode | bw create item > /dev/null
    else
        local item_id
        local existing_notes
        
        item_id=$(echo "$existing_item" | jq -r '.id')
        existing_notes=$(echo "$existing_item" | jq -r '.notes')
        
        if [ "$existing_notes" = "$content" ]; then
            echo -e "${YELLOW}Secrets file in Bitwarden is already up to date.${NC}"
        else
            echo -e "${GREEN}Updating secrets file in Bitwarden.${NC}"
            
            # Create JSON for updated item
            local item_json
            item_json=$(jq -n \
                --arg id "$item_id" \
                --arg notes "$content" \
                '{id: $id, notes: $notes}')
            
            # Update item in Bitwarden
            bw edit item "$item_id" "$item_json" > /dev/null
        fi
    fi
}

# Function to sync private files from Bitwarden to local
sync_private_from_bitwarden() {
    echo -e "${BLUE}Syncing private files from Bitwarden to local...${NC}"
    
    # Get items from Bitwarden with folder "Private" or items with "private" in the name
    local private_items
    private_items=$(bw list items --search "private" | jq -c '.[] | select(.name | test("private|Private|personal|Personal"; "i"))')
    
    if [ -z "$private_items" ]; then
        echo -e "${YELLOW}No private files found in Bitwarden.${NC}"
        return
    fi
    
    echo "$private_items" | while read -r item; do
        local name
        local notes
        local filename
        
        name=$(echo "$item" | jq -r '.name')
        notes=$(echo "$item" | jq -r '.notes')
        
        # Skip if notes are empty
        if [ -z "$notes" ] || [ "$notes" = "null" ]; then
            continue
        fi
        
        # Determine filename from name
        if [[ "$name" =~ Private:\ (.+) ]]; then
            filename="${BASH_REMATCH[1]}"
        fi
        if [[ "$filename" = "" ]]; then
            echo -e "${RED}Error: Could not determine filename from name: $name${NC}"
            continue;
        fi
        
        # Check if file already exists
        if [ ! -f "$PRIVATE_DIR/$filename" ]; then
            echo -e "  ${GREEN}Writing private file: $filename${NC}"
            echo "$notes" > "$PRIVATE_DIR/$filename"
            chmod 600 "$PRIVATE_DIR/$filename"
        else
            echo -e "  ${YELLOW}Private file already exists: $filename${NC}"
        fi
    done
}

# Function to sync private files from local to Bitwarden
sync_private_to_bitwarden() {
    echo -e "${BLUE}Syncing private files from local to Bitwarden...${NC}"
    
    # Get existing private items from Bitwarden
    local existing_private
    existing_private=$(bw list items --search "private" | jq -c '.[] | select(.name | test("private|Private|personal|Personal"; "i")) | .name')
    
    # Find private files in the PRIVATE_DIR
    find "$PRIVATE_DIR" -type f | while read -r file; do
        local filename
        local content
        filename=$(basename "$file")
        content=$(cat "$file")
        
        # Check if private file already exists in Bitwarden
        if echo "$existing_private" | grep -q "\"$filename\"" || echo "$existing_private" | grep -q "\"Private: $filename\""; then
            echo -e "  ${YELLOW}Private file already exists in Bitwarden: $filename${NC}"
        else
            echo -e "  ${GREEN}Adding private file to Bitwarden: $filename${NC}"
            
            # Create JSON for new item
            local item_json
            item_json=$(jq -n \
                --arg name "Private: $filename" \
                --arg notes "$content" \
                '{name: $name, notes: $notes, type: 2, secureNote: {type: 0}}')
            # Add item to Bitwarden
            echo "$item_json" | bw encode | bw create item > /dev/null
        fi
    done
}

main () {
    # Main execution

    echo -e "${GREEN}=== Bitwarden Sync Script ===${NC}"

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is not installed.${NC}"
        echo -e "${YELLOW}Please install jq using your system's package manager.${NC}"
        exit 1
    fi

    # Check if Bitwarden CLI is installed
    if ! command -v bw &> /dev/null; then
        echo -e "${RED}Error: Bitwarden CLI is not installed.${NC}"
        echo -e "${YELLOW}Please install Bitwarden CLI first.${NC}"
        exit 1
    fi

    # Check Bitwarden login status
    check_bw_status

    # Ask for confirmation before proceeding
    echo -e "${YELLOW}This script will sync SSH keys, secrets, and private files between Bitwarden and your local system.${NC}"
    
    # read -p "Do you want to continue? (y/n): " confirm
    # if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    #     echo -e "${RED}Operation cancelled.${NC}"
    #     exit 0
    # fi

    # Perform the sync operations
    sync_ssh_keys_from_bitwarden
    sync_ssh_keys_to_bitwarden
    sync_secrets_from_bitwarden
    sync_secrets_to_bitwarden
    sync_private_from_bitwarden
    sync_private_to_bitwarden

    echo -e "${GREEN}=== Sync completed successfully! ===${NC}"
}
main $@