#!/bin/bash
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ENV_DIR=$(dirname "$SCRIPT_DIR")
source $ENV_DIR/functions/common_funcs

# Configuration variables
REMOTE_REPO="git@github.com:doryashar/encrypted.git"
LOCAL_REPO_PATH="$ENV_DIR/tmp/private_encrypted"
DECRYPTED_DIR="$ENV_DIR/tmp/private"
LOCAL_HASH_FILE="$ENV_DIR/tmp/local_hashes"
TEMP_DIR="$ENV_DIR/tmp/private_encrypted-sync-temp"
# IDENTITY_FILE="$ENV_DIR/tmp/private/age-key"
RECIPIENTS_FILE="$ENV_DIR/tmp/private/age-recipients"

# Function to check if a command exists
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

# Function to ensure age is installed
ensure_age_installed() {
  if ! command_exists age; then
    warning "age encryption tool not found. Attempting to install..."
    
    if command_exists apt-get; then
      sudo apt-get update && sudo apt-get install -y age
    elif command_exists brew; then
      brew install age
    elif command_exists dnf; then
      sudo dnf install -y age
    elif command_exists yum; then
      sudo yum install -y age
    elif command_exists pacman; then
      sudo pacman -S age
    else
      error "Could not automatically install age. Please install it manually."
      error "Visit: https://github.com/FiloSottile/age#installation"
      exit 1
    fi
  fi
  
  debug "age encryption tool is installed."
}

# Function to encrypt a file or directory
encrypt_file() {
  local source="$1"
  local dest="$2"
  
  if [ -d "$source" ]; then
    # Directory encryption - tar first, then encrypt
    tar -cf - -C "$(dirname "$source")" "$(basename "$source")" | age -R "$RECIPIENTS_FILE" > "$dest"
  else
    # File encryption
    age -R "$RECIPIENTS_FILE" -o "$dest" "$source"
  fi
}

# Function to decrypt a file or directory
decrypt_file() {
  local source="$1"
  local dest="$2"
  
  # Create destination directory if it doesn't exist
  mkdir -p "$(dirname "$dest")"
  
  # Decrypt the file
  age -d -i <(echo "$AGE_SECRET") -o "$TEMP_DIR/decrypted_temp" "$source" #Instead of using -i $IDENTITY_FILE

  # Check if it's a tar archive (directory)
  if tar -tf "$TEMP_DIR/decrypted_temp" &> /dev/null; then
    # Extract the tar archive
    mkdir -p "$dest"
    tar -xf "$TEMP_DIR/decrypted_temp" -C "$dest"
  else
    # It's a regular file
    mv "$TEMP_DIR/decrypted_temp" "$dest"
  fi
}

# Function to encrypt recursively
encrypt_recursive() {
  local source_dir="$1"
  local dest_dir="$2"
  
  mkdir -p "$dest_dir"
  
  find "$source_dir" -type f -not -path "*/\.*" | while read -r file; do
    rel_path="${file#$source_dir/}"
    dest_file="$dest_dir/$rel_path.age"
    mkdir -p "$(dirname "$dest_file")"
    encrypt_file "$file" "$dest_file"
    debug "Encrypted: $rel_path"
  done
}

# Function to decrypt recursively
decrypt_recursive() {
  local source_dir="$1"
  local dest_dir="$2"
  
  mkdir -p "$dest_dir"
  
  find "$source_dir" -type f -name "*.age" | while read -r file; do
    rel_path="${file#$source_dir/}"
    rel_path="${rel_path%.age}"  # Remove .age extension
    dest_file="$dest_dir/$rel_path"
    mkdir -p "$(dirname "$dest_file")"
    decrypt_file "$file" "$dest_file"
    info "Decrypted: $rel_path"
  done
}

hashit() {
  dir="$1"
  temp_hash_file="$2"
  find "$dir" -type f -not -path "*/\.*" -printf "%M %TY-%Tm-%Td %TH:%TM:%TS %p\n" -exec sha256sum {} \; | sort > "$temp_hash_file"
}

# Function to check if files have changed
has_changed() {
  local dir="$1"
  local hash_file="$2"
  local temp_hash_file="$TEMP_DIR/temp_hashes"
  
  hashit "$dir" "$temp_hash_file"
  
  if [ ! -f "$hash_file" ]; then
    info "No previous hash file found. Assuming change."
    return 1  # Indicates change (no previous hash)
  fi

  if diff -q "$hash_file" "$temp_hash_file" > /dev/null; then
    return 0  # No change
  else
    # mv "$temp_hash_file" "$hash_file"
    return 1  # Changed
  fi
}

# Function to merge changes
merge_changes() {
  local remote_dir="$1"
  local local_dir="$2"
  local merged_dir="$3"
  local base_dir="$TEMP_DIR/base_files"
  local conflicts_detected=0
  local conflict_files=""
  
  # Check for merge tools
  MERGE_TOOL=""
  for tool in meld kdiff3 vimdiff diffuse tkdiff xxdiff; do
    if command_exists "$tool"; then
      MERGE_TOOL="$tool"
      break
    fi
  done
  
  # Create directories
  mkdir -p "$merged_dir"
  mkdir -p "$base_dir"
  
  # Find all unique files across both directories
  all_files=$(find "$remote_dir" "$local_dir" -type f | sed "s|^$remote_dir/||;s|^$local_dir/||" | sort | uniq)
  
  for rel_path in $all_files; do
    remote_file="$remote_dir/$rel_path"
    local_file="$local_dir/$rel_path"
    merged_file="$merged_dir/$rel_path"
    base_file="$base_dir/$rel_path"
    
    # Ensure directory exists
    mkdir -p "$(dirname "$merged_file")"
    
    # Case 1: File exists only in remote
    if [ ! -f "$local_file" ] && [ -f "$remote_file" ]; then
      cp "$remote_file" "$merged_file"
      info "Added remote-only file: $rel_path"
      continue
    fi
    
    # Case 2: File exists only in local
    if [ -f "$local_file" ] && [ ! -f "$remote_file" ]; then
      cp "$local_file" "$merged_file"
      info "Kept local-only file: $rel_path"
      continue
    fi
    
    # Case 3: File exists in both places
    if [ -f "$local_file" ] && [ -f "$remote_file" ]; then
      if cmp -s "$local_file" "$remote_file"; then
        # Files are identical
        cp "$local_file" "$merged_file"
        info "Files identical: $rel_path"
      else
        # Files differ - need merge
        if [ -f "$base_file" ]; then
          # We have a base version for three-way merge
          git merge-file -p "$local_file" "$base_file" "$remote_file" > "$merged_file"
          if [ $? -eq 0 ]; then
            info "Successfully merged: $rel_path"
          else
            info "Merge conflict in: $rel_path"
            conflicts_detected=1
            conflict_files="$conflict_files $rel_path"
          fi
        else
          # No base version, attempt merge but likely will have conflicts
          git merge-file -p "$local_file" /dev/null "$remote_file" > "$merged_file"
          if [ $? -eq 0 ]; then
            info "Successfully merged: $rel_path"
          else
            info "Merge conflict in: $rel_path (no base version)"
            conflicts_detected=1
            conflict_files="$conflict_files $rel_path"
          fi
        fi
      fi
    fi
  done
  
  # Handle conflicts with interactive merge tool if available
  if [ "$conflicts_detected" -eq 1 ]; then
    info "Conflicts detected in the following files:"
    for file in $conflict_files; do
      info "  - $file"
    done
    
    if [ -n "$MERGE_TOOL" ]; then
      info "Using $MERGE_TOOL for interactive conflict resolution."
      info "Please resolve conflicts in each file when the merge tool opens."
      
      for file in $conflict_files; do
        local_file="$local_dir/$file"
        remote_file="$remote_dir/$file"
        merged_file="$merged_dir/$file"
        base_file="$base_dir/$file"
        
        if [ -f "$base_file" ]; then
          # Three-way merge
          "$MERGE_TOOL" "$local_file" "$base_file" "$remote_file" "$merged_file"
        else
          # Two-way merge
          "$MERGE_TOOL" "$local_file" "$remote_file" "$merged_file"
        fi
        
        if [ $? -ne 0 ]; then
          info "Warning: Merge tool exited with an error for $file"
        fi
      done
    else
      info "No graphical merge tool found. Conflicts are marked in the files with"
      info "<<<<<<< LOCAL VERSION, =======, and >>>>>>> REMOTE VERSION markers."
      info "Please edit the following files manually to resolve conflicts:"
      for file in $conflict_files; do
        info "  - $merged_dir/$file"
      done
      info "Press Enter when you have resolved all conflicts, or Ctrl+C to abort."
      read -r
    fi
  fi
  
  # Validate merged files
  info "Validating merged files..."
  validation_errors=0
  
  for file in $conflict_files; do
    merged_file="$merged_dir/$file"
    if grep -q "<<<<<<< \|=======\|>>>>>>> " "$merged_file"; then
      info "Error: Conflict markers still present in $file"
      validation_errors=1
    fi
  done
  
  if [ "$validation_errors" -eq 1 ]; then
    info "Please resolve all conflicts before continuing."
    info "Press Enter to retry validation, or Ctrl+C to abort."
    read -r
    # Recursive call to validate again
    validate_merged_files "$conflict_files" "$merged_dir"
  else
    info "All conflicts resolved successfully."
  fi
  
  # Save current versions as base for future merges
  for rel_path in $all_files; do
    merged_file="$merged_dir/$rel_path"
    base_file="$base_dir/$rel_path"
    
    if [ -f "$merged_file" ]; then
      mkdir -p "$(dirname "$base_file")"
      cp "$merged_file" "$base_file"
    fi
  done
  
  info "Merge completed and validated."
  info "Merged files are in: $merged_dir"
}

# Helper function to validate merged files recursively
validate_merged_files() {
  local conflict_files="$1"
  local merged_dir="$2"
  local validation_errors=0
  
  for file in $conflict_files; do
    merged_file="$merged_dir/$file"
    if grep -q "<<<<<<< \|=======\|>>>>>>> " "$merged_file"; then
      info "Error: Conflict markers still present in $file"
      validation_errors=1
    fi
  done
  
  if [ "$validation_errors" -eq 1 ]; then
    info "Please resolve all conflicts before continuing."
    info "Press Enter to retry validation, or Ctrl+C to abort."
    read -r
    # Recursive call to validate again
    validate_merged_files "$conflict_files" "$merged_dir"
  else
    info "All conflicts resolved successfully."
  fi
}

get_bw_password() {
    # Read the password from the user
    read -s -p "Enter your BitWarden password: " BW_PASSWORD
    if [ -z "$BW_PASSWORD" ]; then
        error "GitHub master password is required"
        exit 1
    fi
    export BW_PASSWORD
}

get_secret_keys() {
    export BW_EMAIL="dor.yashar@gmail.com"
    BW_STATUS=$(bw status --raw)
    if [[ $BW_STATUS == *"unauthenticated"* ]]; then
        if [ -z "$BW_CLIENTID" ] || [ -z "$BW_CLIENTSECRET" ]; then
            error "Please set the BW_CLIENTID and BW_CLIENTSECRET environment variable. or login to BitWarden"
        fi
        bw login --apikey --raw > /dev/null 2>&1
        if [ $? -ne 0 ]; then
          error "Failed to log in to BitWarden. Please check your credentials."
          exit 1
        fi
    fi

    if [ -z "$BW_SESSION" ] && [[ $BW_STATUS == *"locked"* ]]; then
        if [ -z "$BW_PASSWORD" ]; then
            get_bw_password
        fi
        export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)
        if [ -z "$BW_SESSION" ]; then
          error "Failed to log in to BitWarden. Please check your credentials."
          exit 1
        fi
        info "Logged in successfully!"
    else
        debug "Using existing session."
    fi

    export GITHUB_SSH_PRIVATE_KEY=${GITHUB_SSH_PRIVATE_KEY:-bw get password GITHUB_API_KEY}
    export AGE_SECRET=${AGE_SECRET:-"$(bw get password AGE_SECRET)"}
    if [[ -z "$AGE_SECRET" ]] || [[ -z "$GITHUB_SSH_PRIVATE_KEY" ]]; then
        error "AGE_SECRET/GITHUB_SSH_PRIVATE_KEY is not set. Please set it in your environment."
        exit 1
    fi
}

# Main function
main() {
  title "Synchronizing Private files"
  if  ! command_exists bw; then
    error "Command BW not found, quitting"
    exit 1
  fi
    
  if  ! command_exists bw; then
    error "Command BW not found, quitting"
    exit 1
  fi
    
  # Ensure age is installed
  debug "Ensuring AGE is installed and setting up the secret from BW"
  ensure_age_installed
  get_secret_keys

  # Create necessary directories
  mkdir -p "$TEMP_DIR"
  
  # if github_access_denied; then
  #   GITHUB_SSH_PRIVATE_KEY=${GITHUB_SSH_PRIVATE_KEY:-bw get password GITHUB_SSH_PRIVATE_KEY}
  #   TEMP_SSH_IDENTITY_FILE=$(mktemp); chmod 600 $TEMP_SSH_IDENTITY_FILE; 
  #   echo -e $GITHUB_SSH_PRIVATE_KEY > $TEMP_SSH_IDENTITY_FILE
  #   TEMP_SSH_FILE=$(mktemp); chmod +x $TEMP_SSH_FILE; 
  #   echo "ssh -i $TEMP_SSH_IDENTITY_FILE " '$@' > $TEMP_SSH_FILE
  #   echo executable: $TEMP_SSH_FILE
  #   GIT_SSH="$TEMP_SSH_FILE" 
  # fi

  if [ ! -d "$DECRYPTED_DIR" ]; then
    # Initial decrypt after clone

    # Setup local repo if it doesn't exist
    if [ ! -d "$LOCAL_REPO_PATH" ]; then
      info "Initializing local repository..."
      mkdir -p "$LOCAL_REPO_PATH"
      temp_gz=$(mktemp)
      curl -H "Authorization: token $GITHUB_API_TOKEN" \
          -L https://api.github.com/repos/doryashar/encrypted/tarball \
          -o $temp_gz
      tar xzf $temp_gz -C "$LOCAL_REPO_PATH" --strip-components=1
      rm $temp_gz
    fi

    
    info "Initial Decrypting now from $LOCAL_REPO_PATH to $DECRYPTED_DIR"
    decrypt_recursive "$LOCAL_REPO_PATH" "$DECRYPTED_DIR"
    hashit "$DECRYPTED_DIR" "$LOCAL_HASH_FILE"
    #TODO: remove
    rm -rf ~/.ssh
    ln -s "$DECRYPTED_DIR"/ssh ~/.ssh
    chmod -R 600 $LOCAL_REPO_PATH
  fi
  
  
  if [ ! -d "$LOCAL_REPO_PATH"/.git ]; then 
    info "setting up git in encrypted dir"
    rm -rf "$LOCAL_REPO_PATH" || exit 1
    mkdir -p  "$LOCAL_REPO_PATH" && git clone git@github.com:doryashar/encrypted.git "$LOCAL_REPO_PATH" || error "Could not glone git repo $REMOTE_REPO" && exit 1
    hashit "$DECRYPTED_DIR" "$LOCAL_HASH_FILE"
    exit 0
  fi
#   local_changed=$(git status --porcelain | wc -l)
#   local_changed=$([ -n "$(git status --porcelain)" ] && info 1 || info 0)

  # Check for remote changes
  cd "$LOCAL_REPO_PATH" || exit 1
  debug "Checking for remote changes..."
  git fetch || exit 1
  debug "Checking if there are any updates in local"
  local_current=$(git rev-parse HEAD)
  debug "Checking if there are any updates in remote"
  remote_current=$(git rev-parse @{upstream})
  
  remote_changed=0
    
  if [ ! -d "$DECRYPTED_DIR" ]; then
    info "Decrypted directory not found. Assuming remote has changes."
    remote_changed=1
  elif [ "$local_current" != "$remote_current" ]; then
    info "Remote has changes."
    remote_changed=1
  else
    debug "Remote is up-to-date."
  fi
  
  # Check if local decrypted files changed
  debug "Checking for local changes..."
  local_changed=0

  if [ ! -d "$DECRYPTED_DIR" ]; then
    debug "Will not check for local changes, as decrypted dir does not exist"
  if has_changed "$DECRYPTED_DIR" "$LOCAL_HASH_FILE"; then
    debug "Local files unchanged."
  else
    info "Local files have changed."
    local_changed=1
  fi

  # # If CHECK_ONLY does not exist, set it to 0
  # CHECK_ONLY=${CHECK_ONLY:-1}
  # if [ "$CHECK_ONLY" -eq 1 ]; then
  #   exit 0
  # fi

  # Case 1: No changes anywhere
  if [ "$remote_changed" -eq 0 ] && [ "$local_changed" -eq 0 ]; then
    debug "No changes detected. Nothing to do."
    exit 0
  fi
  
  # Reset LOCAL_REPO_PATH to github head
  cd "$LOCAL_REPO_PATH" || exit 1
  git reset --hard HEAD && git clean -fd


  # Case 2: Only remote changed
  if [ "$remote_changed" -eq 1 ] && [ "$local_changed" -eq 0 ]; then
    info "Only remote has changed. Updating local files..."
    git pull
    rm -rf "$DECRYPTED_DIR"/*
    decrypt_recursive "$LOCAL_REPO_PATH" "$DECRYPTED_DIR"
    hashit "$DECRYPTED_DIR" "$LOCAL_HASH_FILE"
    debug "Local files updated successfully."
    exit 0
  fi
  
  # Case 3: Only local changed
  if [ "$remote_changed" -eq 0 ] && [ "$local_changed" -eq 1 ]; then
    info "Only local files have changed. Encrypting and pushing..."
    #TODO: sync only files that were changed / added / removed

    # Remove old encrypted files
    find "$LOCAL_REPO_PATH" -name "*.age" -type f -delete
    
    # Encrypt all decrypted files
    encrypt_recursive "$DECRYPTED_DIR" "$LOCAL_REPO_PATH"
    
    # Commit and push
    cd "$LOCAL_REPO_PATH" || exit 1
    git add .
    git commit -m "Update encrypted files: $(date)"
    git push
    if [ $? -ne 0 ]; then
      error "Failed to push changes."
      exit 1
    fi
    mv "$TEMP_DIR/temp_hashes" "$LOCAL_HASH_FILE"
    debug "Local changes encrypted and pushed successfully."
    exit 0
  fi
  
  # Case 4: Both changed
  if [ "$remote_changed" -eq 1 ] && [ "$local_changed" -eq 1 ]; then
    info "Both remote and local files have changed. Merging..."
    rm "$TEMP_DIR/temp_hashes"

    # Create temporary directory for remote files
    REMOTE_TEMP="$TEMP_DIR/remote_decrypted"
    mkdir -p "$REMOTE_TEMP"
    
    # Save current state
    git stash
    
    # Get remote version
    git pull
    
    # Decrypt remote files
    decrypt_recursive "$LOCAL_REPO_PATH" "$REMOTE_TEMP"
    
    # Pop the stash to revert to our local state
    git stash pop
    
    # Merged directory
    MERGED_DIR="$TEMP_DIR/merged"
    rm -rf "$MERGED_DIR"
    mkdir -p "$MERGED_DIR"
    
    # Merge changes
    merge_changes "$REMOTE_TEMP" "$DECRYPTED_DIR" "$MERGED_DIR"
    
    # Remove old decrypted and encrypted files
    rm -rf "$DECRYPTED_DIR"/*
    find "$LOCAL_REPO_PATH" -name "*.age" -type f -delete
    
    # Copy merged files to decrypted directory
    cp -R "$MERGED_DIR/"* "$DECRYPTED_DIR/" 2>/dev/null || true
    
    # Encrypt merged files
    encrypt_recursive "$DECRYPTED_DIR" "$LOCAL_REPO_PATH"
    
    # Update hash file
    hashit "$DECRYPTED_DIR" "$LOCAL_HASH_FILE"
    
    # Commit and push
    cd "$LOCAL_REPO_PATH" || exit 1
    git add .
    git commit -m "Merge changes: $(date)"
    git push
    
    debug "Files merged, encrypted, and pushed successfully."
    exit 0
  fi
}

# Cleanup function
cleanup() {
  debug "Cleaning up temporary files..."
  rm -rf "$TEMP_DIR"
  debug "Done cleanup."
}

# Set cleanup on exit
trap cleanup EXIT

# Run main function
main

