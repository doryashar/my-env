#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ENV_DIR=$(dirname "$SCRIPT_DIR")
source $ENV_DIR/functions/common_funcs

mkdir -p ~/.ssh
ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null

# Load configuration (including BW_EMAIL)
if [[ -f "$ENV_DIR/config/repo.conf" ]]; then
    source "$ENV_DIR/config/repo.conf"
fi

# Configuration variables
REMOTE_REPO="${PRIVATE_URL:-git@github.com:doryashar/encrypted.git}"
LOCAL_REPO_PATH="$ENV_DIR/tmp/private_encrypted"
DECRYPTED_DIR="$ENV_DIR/tmp/private"
LOCAL_HASH_FILE="$ENV_DIR/tmp/local_hashes"
TEMP_DIR="$ENV_DIR/tmp/private_encrypted-sync-temp"
# IDENTITY_FILE="$ENV_DIR/tmp/private/age-key"
RECIPIENTS_FILE="$ENV_DIR/tmp/private/age-recipients"

# Check if a command exists in PATH
#
# Args:
#   $1 - Command name to check
#
# Returns:
#   0 - Command exists
#   1 - Command does not exist
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

# Ensure age encryption tool is installed
#
# Attempts to install age using the system's package manager if not found.
#
# Returns:
#   0 - Age is installed
#   1 - Failed to install age
#
# Side Effects:
#   - May invoke sudo to install packages
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

# Encrypt a file or directory using age
#
# Args:
#   $1 - Source file or directory path
#   $2 - Destination encrypted file path (.age extension)
#
# Returns:
#   0 - Success
#   Non-zero on encryption failure
#
# Side Effects:
#   - Creates encrypted file at destination
#   - Directories are tar'd before encryption
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

# Decrypt a file or directory using age
#
# Args:
#   $1 - Source encrypted file path (.age)
#   $2 - Destination path for decrypted content
#
# Returns:
#   0 - Success
#   Non-zero on decryption failure
#
# Side Effects:
#   - Creates destination directory if needed
#   - Extracts tar archives if source is a directory
#   - Creates unique temp file during decryption
decrypt_file() {
  local source="$1"
  local dest="$2"
  local temp_file
  temp_file=$(mktemp "${TEMP_DIR}/decrypted_temp.XXXXXX")

  # Create destination directory if it doesn't exist
  mkdir -p "$(dirname "$dest")"

  # Decrypt the file
  age -d -i <(echo "$AGE_SECRET") -o "$temp_file" "$source" #Instead of using -i $IDENTITY_FILE

  # Check if it's a tar archive (directory)
  if tar -tf "$temp_file" &> /dev/null; then
    # Extract the tar archive
    mkdir -p "$dest"
    tar -xf "$temp_file" -C "$dest"
  else
    # It's a regular file
    mv "$temp_file" "$dest"
  fi

  # Clean up temp file
  rm -f "$temp_file"
}

# Encrypt all files in a directory recursively
#
# Args:
#   $1 - Source directory path
#   $2 - Destination directory path
#
# Returns:
#   0 - Success
#
# Side Effects:
#   - Creates .age files for each file in source
#   - Skips hidden files (starting with .)
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

# Decrypt all .age files in a directory recursively
#
# Args:
#   $1 - Source directory with .age files
#   $2 - Destination directory path
#
# Returns:
#   0 - Success
#
# Side Effects:
#   - Removes .age extension from decrypted files
#   - Creates destination directory structure
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

# Generate hash file for directory contents
#
# Args:
#   $1 - Directory path to hash
#   $2 - Output hash file path
#
# Returns:
#   0 - Success
#
# Side Effects:
#   - Creates hash file with permissions, timestamps, paths, and SHA256 hashes
hashit() {
  dir="$1"
  temp_hash_file="$2"
  find "$dir" -type f -not -path "*/\.*" -printf "%M %TY-%Tm-%Td %TH:%TM:%TS %p\n" -exec sha256sum {} \; | sort > "$temp_hash_file"
}

# Check if files in directory have changed since last hash
#
# Args:
#   $1 - Directory path to check
#   $2 - Previous hash file path
#
# Returns:
#   0 - No changes detected
#   1 - Changes detected or no previous hash exists
#
# Side Effects:
#   - Creates temp hash file for comparison
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

# Merge changes between remote and local directories
#
# Args:
#   $1 - Remote directory path
#   $2 - Local directory path
#   $3 - Output merged directory path
#
# Returns:
#   0 - Success
#
# Side Effects:
#   - Creates merged directory with combined changes
#   - May launch interactive merge tool for conflicts
#   - Saves base versions for future merges
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

# Validate that conflict markers were removed from merged files
#
# Args:
#   $1 - Space-separated list of files to validate
#   $2 - Merged directory path
#
# Returns:
#   0 - All conflicts resolved
#   1 - Conflicts still present (recursive)
#
# Side Effects:
#   - Prompts user to retry if conflicts remain
#   - Recursive calls itself until validation passes
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

# Prompt user for Bitwarden password
#
# Returns:
#   0 - Success
#   1 - Empty password provided (exits)
#
# Side Effects:
#   - Sets BW_PASSWORD environment variable
#   - Exits if password is empty
get_bw_password() {
    if [[ -t 0 ]]; then
        read -s -p "Enter your BitWarden password: " BW_PASSWORD
    else
        echo -n "Enter your BitWarden password: "
        read -s BW_PASSWORD < /dev/tty
    fi
    if [ -z "$BW_PASSWORD" ]; then
        error "Bitwarden master password is required"
        exit 1
    fi
    export BW_PASSWORD
}

# Retrieve AGE_SECRET using fallback chain
#
# Checks in order:
#   1. AGE_SECRET environment variable
#   2. ~/.config/age/secret file
#   3. Bitwarden (if BW_SESSION available)
#   4. Interactive prompt (if TTY available)
#
# Returns:
#   0 - Success (AGE_SECRET is set)
#   1 - Failed to get AGE_SECRET
#
# Side Effects:
#   - Sets AGE_SECRET environment variable
get_age_secret() {
    if [[ -n "${AGE_SECRET:-}" ]]; then
        debug "Using AGE_SECRET from environment"
        return 0
    fi

    local secret_file="$HOME/.config/age/secret"
    if [[ -f "$secret_file" ]]; then
        export AGE_SECRET=$(cat "$secret_file")
        debug "Using AGE_SECRET from $secret_file"
        return 0
    fi

    if [[ -n "${BW_SESSION:-}" ]] && command_exists bw; then
        local secret
        secret=$(bw get password AGE_SECRET 2>/dev/null || echo "")
        if [[ -n "$secret" ]]; then
            export AGE_SECRET="$secret"
            debug "Using AGE_SECRET from Bitwarden"
            return 0
        fi
    fi

    if [[ -t 0 ]] || [[ -c /dev/tty ]]; then
        echo -n "Enter AGE_SECRET (encryption key): "
        if [[ -t 0 ]]; then
            read -rs AGE_SECRET
        else
            read -rs AGE_SECRET < /dev/tty
        fi
        echo
        if [[ -n "$AGE_SECRET" ]]; then
            export AGE_SECRET
            debug "Using AGE_SECRET from manual input"
            return 0
        fi
    fi

    return 1
}

# Authenticate with Bitwarden and retrieve secret keys
#
# Returns:
#   0 - Success
#   1 - Authentication failed (exits)
#
# Side Effects:
#   - Sets BW_SESSION environment variable
#   - Sets GITHUB_SSH_PRIVATE_KEY environment variable
#   - Sets AGE_SECRET environment variable
#   - May call get_bw_password() if session is locked
get_secret_keys() {
    if get_age_secret; then
        debug "AGE_SECRET obtained via fallback chain"
    else
        if [[ "${BW_AUTH_STATUS:-}" == "skipped" ]]; then
            debug "Bitwarden skipped in parent process"
            return 1
        fi

        if [[ "${BW_AUTH_STATUS:-}" == "failed" ]]; then
            debug "Bitwarden auth failed in parent process"
            return 1
        fi

        if [[ -n "${BW_SESSION:-}" ]] && bw get status &>/dev/null; then
            debug "Using existing BW_SESSION from parent process"
        else
            if [[ -z "${BW_EMAIL:-}" ]]; then
                warning "BW_EMAIL environment variable not set. Please add it to config/repo.conf"
                echo ""
                echo "Would you like to continue without Bitwarden?"
                if prompt_yn "Skip Bitwarden? (y/n) "; then
                    return 1
                fi
                return 1
            fi
            
            BW_STATUS=$(bw status --raw)
            if [[ $BW_STATUS == *"unauthenticated"* ]]; then
                if [ -n "${BW_CLIENTID:-}" ] && [ -n "${BW_CLIENTSECRET:-}" ]; then
                    info "Logging in to Bitwarden with OAuth2..."
                    bw login --apikey --raw > /dev/null 2>&1 || {
                        warning "OAuth2 login failed"
                    }
                else
                    warning "BW_CLIENTID and BW_CLIENTSECRET not set"
                    echo ""
                    echo "Would you like to login to Bitwarden manually?"
                    if prompt_yn "Login to Bitwarden? (y/n) "; then
                        if bw login; then
                            info "Logged in to Bitwarden"
                        else
                            warning "Bitwarden login failed"
                            return 1
                        fi
                    else
                        info "Continuing without Bitwarden..."
                        return 1
                    fi
                fi
            fi

            BW_STATUS=$(bw status --raw)
            if [ -z "${BW_SESSION:-}" ] && [[ $BW_STATUS == *"locked"* ]]; then
                if [ -z "${BW_PASSWORD:-}" ]; then
                    get_bw_password
                fi
                export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)
                if [ -z "${BW_SESSION:-}" ]; then
                    warning "Failed to unlock Bitwarden vault"
                    return 1
                fi
                info "Vault unlocked successfully!"
            else
                debug "Using existing BitWarden session."
            fi
        fi

        if ! get_age_secret; then
            warning "Could not retrieve AGE_SECRET"
            return 1
        fi
    fi

    if [[ -n "${BW_SESSION:-}" ]] && command_exists bw; then
        export GITHUB_SSH_PRIVATE_KEY=${GITHUB_SSH_PRIVATE_KEY:-$(bw get password GITHUB_API_KEY 2>/dev/null || echo "")}
    fi

    return 0
}

# Display changed files and allow viewing diffs
#
# Args:
#   $1 - Type of changes: "remote" or "local"
#   $2 - Optional: temp directory with remote decrypted files (for remote changes)
#
# Returns:
#   0 - User confirmed to proceed
#   1 - User chose to abort
#
# Side Effects:
#   - Displays changed files
#   - Allows user to view diffs interactively
show_changed_files_and_confirm() {
    local change_type="$1"
    local remote_temp_dir="${2:-}"
    local changed_files=()
    local file_index=1

    if [ "$change_type" = "remote" ]; then
        title "Remote Changes Detected"
        echo ""
        info "The following files have changed remotely:"
        echo ""

        cd "$LOCAL_REPO_PATH" || exit 1
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            base_name="${file%.age}"
            changed_files+=("$base_name")
            echo "  [$file_index] $base_name"
            ((file_index++))
        done < <(git diff --name-only HEAD @{upstream} 2>/dev/null)

    elif [ "$change_type" = "local" ]; then
        title "Local Changes Detected"
        echo ""
        info "The following files have changed locally:"
        echo ""

        local temp_hash_file="$TEMP_DIR/temp_hashes_local"
        hashit "$DECRYPTED_DIR" "$temp_hash_file"

        while IFS= read -r local_file; do
            [ -z "$local_file" ] && continue
            changed_files+=("$local_file")
            echo "  [$file_index] $local_file"
            ((file_index++))
        done < <(diff "$LOCAL_HASH_FILE" "$temp_hash_file" 2>/dev/null | grep "^>" | awk '{for (i=3; i<=NF; i++) printf $i " "; print ""}' | sed 's/ $//')
    fi

    if [ ${#changed_files[@]} -eq 0 ]; then
        echo "  No specific file changes detected."
        return 0
    fi

    echo ""
    echo "Options:"
    echo "  [1-${#changed_files[@]}] - View diff for specific file"
    echo "  [a]             - View all diffs"
    echo "  [y]             - Proceed with sync"
    echo "  [n]             - Cancel sync"
    echo ""
    prompt "Choose an option: " choice

    case "$choice" in
        [yY])
            echo ""
            return 0
            ;;
        [nN])
            echo ""
            info "Sync cancelled by user."
            exit 0
            ;;
        [aA])
            echo ""
            if [ "$change_type" = "remote" ]; then
                for file in "${changed_files[@]}"; do
                    show_file_diff "$file" "remote"
                done
            else
                for file in "${changed_files[@]}"; do
                    show_file_diff "$file" "local"
                done
            fi
            ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#changed_files[@]} ]; then
                local selected_file="${changed_files[$((choice-1))]}"
                show_file_diff "$selected_file" "$change_type"
            else
                error "Invalid option. Please try again."
                show_changed_files_and_confirm "$change_type" "$remote_temp_dir"
                return $?
            fi
            ;;
    esac

    echo ""
    if prompt_yn "Do you want to proceed with the sync? (y/n) "; then
        return 0
    else
        info "Sync cancelled by user."
        exit 0
    fi
}

# Show diff for a specific file
#
# Args:
#   $1 - File path (relative)
#   $2 - Type: "remote" or "local"
#
# Returns:
#   0 - Success
show_file_diff() {
    local file="$1"
    local change_type="$2"
    local encrypted_file="${file}.age"

    echo ""
    title "Diff for: $file"
    echo ""

    if [ "$change_type" = "remote" ]; then
        local temp_file="$TEMP_DIR/remote_decrypted_temp_$$.txt"

        git show HEAD:"$encrypted_file" 2>/dev/null | age -d -i <(echo "$AGE_SECRET") -o "$TEMP_DIR/current_decrypted" 2>/dev/null || true
        git show @{upstream}:"$encrypted_file" 2>/dev/null | age -d -i <(echo "$AGE_SECRET") -o "$TEMP_DIR/remote_decrypted" 2>/dev/null || true

        if [ -f "$TEMP_DIR/current_decrypted" ] && [ -f "$TEMP_DIR/remote_decrypted" ]; then
            if command_exists diff; then
                diff -u "$TEMP_DIR/current_decrypted" "$TEMP_DIR/remote_decrypted" || true
            else
                echo "Current version:"
                cat "$TEMP_DIR/current_decrypted"
                echo ""
                echo "Remote version:"
                cat "$TEMP_DIR/remote_decrypted"
            fi
        fi

        rm -f "$TEMP_DIR/current_decrypted" "$TEMP_DIR/remote_decrypted"
    else
        local temp_hash_file="$TEMP_DIR/temp_hashes_local"
        hashit "$DECRYPTED_DIR" "$temp_hash_file"
        
        echo "Changes detected in local file."
        if [ -f "$DECRYPTED_DIR/$file" ]; then
            echo "Current content:"
            cat "$DECRYPTED_DIR/$file"
        fi
    fi

    echo ""
    if [[ -t 0 ]]; then
        read -p "Press Enter to continue..."
    else
        echo "Press Enter to continue..."
        read < /dev/tty
    fi
}

# Main entry point for encrypted files synchronization
#
# Handles:
#   - Bitwarden authentication
#   - Age encryption/decryption
#   - Git operations on encrypted repository
#   - Merge conflict resolution
#
# Returns:
#   0 - Success
#   Non-zero on failure
#
# Side Effects:
#   - May create/update DECRYPTED_DIR
#   - May commit/push changes to remote
#   - Registers cleanup trap on EXIT
main() {
  title "Synchronizing Private files"

  if ! ensure_github_auth; then
    error "GitHub authentication required to sync encrypted files"
    exit 1
  fi

  if ! check_github_repo_exists "$REMOTE_REPO"; then
    error "Private repository does not exist: $REMOTE_REPO"
    echo ""
    echo "Please run setup.sh to create the private repository:"
    echo "  ~/env/scripts/setup.sh"
    echo ""
    echo "Or manually create a private repo and update PRIVATE_URL in ~/env/config/repo.conf"
    exit 1
  fi

  if ! command_exists bw; then
    error "Command BW not found, quitting"
    exit 1
  fi
    
  # Ensure age is installed
  debug "Ensuring AGE is installed and setting up the secret from BW"
  ensure_age_installed
  
  if ! get_secret_keys; then
    if [[ -z "${BW_AUTH_STATUS:-}" ]]; then
      warning "Bitwarden authentication skipped or failed"
      echo ""
      echo "Encrypted files sync requires Bitwarden. You can:"
      echo "  1. Set BW_EMAIL, BW_CLIENTID, BW_CLIENTSECRET in your environment"
      echo "  2. Run: bw login"
      echo "  3. Re-run this script after authenticating"
    else
      debug "Bitwarden unavailable, skipping encrypted sync"
    fi
    exit 0
  fi

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
      temp_gz=$(mktemp) || exit 1
      curl -H "Authorization: token $GITHUB_SSH_PRIVATE_KEY" \
          -L https://api.github.com/repos/doryashar/encrypted/tarball \
          -o "$temp_gz" || exit 1
      tar xzf "$temp_gz" -C "$LOCAL_REPO_PATH" --strip-components=1 || exit 1
      rm -f "$temp_gz"
    fi

    
    info "Initial Decrypting now from $LOCAL_REPO_PATH to $DECRYPTED_DIR"
    decrypt_recursive "$LOCAL_REPO_PATH" "$DECRYPTED_DIR"
    hashit "$DECRYPTED_DIR" "$LOCAL_HASH_FILE"
    #TODO: the script should also set the file permissions
    if [[ -d ~/.ssh ]]; then
      if [[ -L ~/.ssh ]]; then
        rm ~/.ssh
      else
        warning "Existing ~/.ssh is a directory, not a symlink"
        if prompt_yn "Replace it? [y/N] "; then
          backup_dir=~/.ssh.backup.$(date +%Y%m%d_%H%M%S)
          info "Backing up ~/.ssh to $backup_dir"
          mv ~/.ssh "$backup_dir"
        else
          error "Aborted. Please manually backup ~/.ssh and re-run."
        fi
      fi
    fi
    ln -s "$DECRYPTED_DIR"/ssh ~/.ssh
    chmod 600 "$DECRYPTED_DIR"/ssh/*
    chmod 600 "$DECRYPTED_DIR"/ssh/secrets
  fi
  
  
  if [ ! -d "$LOCAL_REPO_PATH"/.git ]; then 
    info "setting up git in encrypted dir"
    rm -rf "$LOCAL_REPO_PATH" || exit 1
    mkdir -p  "$LOCAL_REPO_PATH" && git clone git@github.com:doryashar/encrypted.git "$LOCAL_REPO_PATH" || error "Could not clone git repo $REMOTE_REPO"
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
    
  # if [ ! -d "$DECRYPTED_DIR" ]; then
  #   info "Decrypted directory not found. Assuming remote has changes."
  #   remote_changed=1
  # el
  if [ "$local_current" != "$remote_current" ]; then
    info "Remote has changes."
    remote_changed=1
  else
    debug "Remote is up-to-date."
  fi
  
  # Check if local decrypted files changed
  debug "Checking for local changes..."
  local_changed=0

  # if [ ! -d "$DECRYPTED_DIR" ]; then
  #   debug "Will not check for local changes, as decrypted dir does not exist"
  # el
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
    show_changed_files_and_confirm "remote"

    info "Pulling remote changes..."
    git pull
    rm -rf "$DECRYPTED_DIR"/*
    decrypt_recursive "$LOCAL_REPO_PATH" "$DECRYPTED_DIR"
    hashit "$DECRYPTED_DIR" "$LOCAL_HASH_FILE"
    debug "Local files updated successfully."
    exit 0
  fi
  
  # Case 3: Only local changed
  if [ "$remote_changed" -eq 0 ] && [ "$local_changed" -eq 1 ]; then
    show_changed_files_and_confirm "local"

    info "Encrypting and pushing local changes..."

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
    title "Both Remote and Local Changes Detected"
    echo ""

    # Show local changes
    local changed_files=()
    local file_index=1
    info "Local changes:"
    echo ""
    local temp_hash_file="$TEMP_DIR/temp_hashes_local"
    hashit "$DECRYPTED_DIR" "$temp_hash_file"
    while IFS= read -r local_file; do
        [ -z "$local_file" ] && continue
        changed_files+=("$local_file")
        echo "  [$file_index] $local_file"
        ((file_index++))
    done < <(diff "$LOCAL_HASH_FILE" "$temp_hash_file" 2>/dev/null | grep "^>" | awk '{for (i=3; i<=NF; i++) printf $i " "; print ""}' | sed 's/ $//')

    # Show remote changes
    echo ""
    info "Remote changes:"
    echo ""
    cd "$LOCAL_REPO_PATH" || exit 1
    local remote_index=1
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        base_name="${file%.age}"
        changed_files+=("$base_name (remote)")
        echo "  [$remote_index] $base_name"
        ((remote_index++))
    done < <(git diff --name-only HEAD @{upstream} 2>/dev/null)

    if [ ${#changed_files[@]} -eq 0 ]; then
        echo "  No specific file changes detected."
    fi

    echo ""
    if prompt_yn "Do you want to merge and push the changes? (y/n) "; then
        :
    else
        info "Sync cancelled by user."
        exit 0
    fi

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

# Cleanup temporary files on exit
#
# Called automatically by trap on EXIT
#
# Returns:
#   0 - Success
#
# Side Effects:
#   - Removes TEMP_DIR
cleanup() {
  debug "Cleaning up temporary files..."
  rm -rf "$TEMP_DIR"
  debug "Done cleanup."
}

# Set cleanup on exit
trap cleanup EXIT

# Run main function
main

