#!/bin/bash

#########################################################################
# Dotfiles Synchronizer
# 
# This script synchronizes dotfiles between your local system and a git
# repository. It supports bidirectional syncing, automatic conflict resolution,
# and customizable link types (hard/soft).
#
# Features:
# - Configurable source-to-target mapping
# - Auto-creation of missing configuration
# - Git integration for version control
# - Smart conflict resolution based on modification time
# - Support for both hard and soft links
# - Regular expression support for file matching
#########################################################################

# Declare variables
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ENV_DIR=$(dirname "$SCRIPT_DIR")
REMOTE_URL="https://github.com/doryashar/my_env"
CONFIG_FILE="$ENV_DIR/config/dotfiles.conf"

# Default configuration path
REPO_PATH="${ENV_DIR/#\~/$HOME}"
DEFAULT_LINK_TYPE="soft"
DEFAULT_CONFLICT_STRATEGY="ask"

# Parse the mapping lines
declare -A SOURCE_TO_TARGET
declare -A FILE_OPTIONS
SOURCE_REGEX=()
TARGET_REGEX=()
BACKWARD_SYNC=()

DEBUG=1

## ====================================== ##
source $ENV_LOC/functions/common_funcs
## ====================================== ##

# Function to display usage information
show_help() {
    echo -e "${BLUE}Dotfiles Synchronizer${NC}"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help                Show this help message"
    echo "  -i, --init                Initialize new dotfiles repository"
    echo "  -c, --config FILE         Use alternative config file"
    echo "  -r, --repo PATH           Set git repository path"
    echo "  -l, --pull                Pull changes from remote repository"
    echo "  -d, --dotfiles_sync       Sync dotfiles between local and repo"
    echo "  -e, --encrypted_sync      Sync encrypted files with remote repo"
    echo "  -p, --push                Push changes to remote repository"
    echo ""
}

# Function to create default config file
create_default_config() {
    local config_path="$1"
    
    if [[ -f "$config_path" ]]; then
        echo -e "${YELLOW}Config file already exists at $config_path${NC}"
        return 0
    fi
    
    echo -e "${GREEN}Creating default configuration at $config_path${NC}"
    
    cat > "$config_path" << EOF
# Dotfiles Synchronizer Configuration

#########################################################################
# Global settings
#########################################################################

# Repository path (where dotfiles are stored in git)
# REPO_PATH="$REPO_PATH"

#TODO: Add sync option
# Default link type (soft or hard)
DEFAULT_LINK_TYPE="$DEFAULT_LINK_TYPE"

# Default conflict resolution strategy
# Options: ask, local, remote, rename, ignore
DEFAULT_CONFLICT_STRATEGY="$DEFAULT_CONFLICT_STRATEGY"

# Remote git repository URL (optional)
REMOTE_URL=""

#########################################################################
# File mappings
# Format: SOURCE => TARGET  or  SOURCE <= TARGET
# 
# SOURCE paths are relative to REPO_PATH
# TARGET paths can be absolute or relative to HOME
#
# Forward sync (=>): Copy/link from repo to system
# Backward sync (<=): Copy from system to repo
#
# Regular expressions:
# - Use (*) in source and \$1 in target for capture groups
# - Use * for simple wildcards
#########################################################################

# Direct mappings
bash/.bashrc => $HOME/.bashrc
bash/.bash_profile => $HOME/.bash_profile
bash/.bash_aliases => $HOME/.bash_aliases

# Regex mappings (wildcard)
vim/* => $HOME/.vim/*

# Regex mappings (capture groups)
config/(.*) => $HOME/.config/\$1

# Backward sync (system to repo)
custom/local_settings <= $HOME/.local_settings

# Wildcard backward sync
custom/bin/* <= $HOME/bin/*

# Add more mappings as needed
EOF

    echo -e "${GREEN}Default configuration created. Please edit $config_path to customize your setup.${NC}"
    exit 0
}

# Initialize git repository for dotfiles
init_repo() {
    local repo_path="$1"
    
    if [[ -d "$repo_path/.git" ]]; then
        echo -e "${YELLOW}Repository already initialized at $repo_path${NC}"
        return 0
    fi
    
    mkdir -p "$repo_path"
    cd "$repo_path" || exit 1
    
    git init
    touch README.md
    echo "# Dotfiles" > README.md
    echo "My personal dotfiles managed with Dotfiles Synchronizer" >> README.md
    
    # Create basic structure
    mkdir -p bash vim git
    
    git add README.md
    git commit -m "Initial commit"
    
    echo -e "${GREEN}Repository initialized at $repo_path${NC}"
    echo "Edit your config file to add your dotfiles."
    
    return 0
}

# Parse and load configuration
load_config() {
    local config_path="$1"
    
    if [[ ! -f "$config_path" ]]; then
        echo -e "${YELLOW}Config file not found at $config_path${NC}"
        create_default_config "$config_path"
    fi
    
    # Clear existing arrays to avoid stale data
    SOURCE_TO_TARGET=()
    FILE_OPTIONS=()
    SOURCE_REGEX=()
    TARGET_REGEX=()
    BACKWARD_SYNC=()

    # Source the config file for variables only
    # We'll parse the mappings manually
    # Extract global variables only, not the mappings
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        
        # Only process variable assignments (not mappings)
        if [[ "$line" =~ ^([A-Z_]+)=\"?([^\"]*)\"?$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            # Use eval to set the variable
            eval "$var_name=\"$var_value\""
        fi
    done < "$config_path"
    
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        
        # Skip variable assignments (already processed)
        [[ "$line" =~ ^[A-Z_]+=.*$ ]] && continue
        
        # Parse backward sync mappings: SOURCE <= TARGET [OPTIONS]
        if [[ "$line" =~ ([^=]+)\ *\<=\ *(.+) ]]; then
            local source="${BASH_REMATCH[1]}"
            local target="${BASH_REMATCH[2]}"
            
            # Clean up whitespace
            source=$(echo "$source" | xargs)
            target=$(echo "$target" | xargs)
            
            # Store in backward sync array
            BACKWARD_SYNC+=("$source <= $target")
            FILE_OPTIONS["$source <= $target"]="link=$DEFAULT_LINK_TYPE conflict=$DEFAULT_CONFLICT_STRATEGY"
            continue
        fi

        # Parse mapping lines: SOURCE => TARGET [OPTIONS]
        if [[ "$line" =~ (.+)\ *=\>\ *(.+) ]]; then
            # debug "Mapping found: ${BASH_REMATCH[1]} => ${BASH_REMATCH[2]}"
            local source="${BASH_REMATCH[1]}"
            local target_and_options="${BASH_REMATCH[2]}"
            
            # Extract target and options
            if [[ "$target_and_options" =~ (.+)\ +link=([a-z]+)\ +conflict=([a-z]+) ]]; then
                local target="${BASH_REMATCH[1]}"
                local link_type="${BASH_REMATCH[2]}"
                local conflict_strategy="${BASH_REMATCH[3]}"
            elif [[ "$target_and_options" =~ (.+)\ +link=([a-z]+) ]]; then
                local target="${BASH_REMATCH[1]}"
                local link_type="${BASH_REMATCH[2]}"
                local conflict_strategy="$DEFAULT_CONFLICT_STRATEGY"
            elif [[ "$target_and_options" =~ (.+)\ +conflict=([a-z]+) ]]; then
                local target="${BASH_REMATCH[1]}"
                local link_type="$DEFAULT_LINK_TYPE"
                local conflict_strategy="${BASH_REMATCH[2]}"
            else
                local target="$target_and_options"
                local link_type="$DEFAULT_LINK_TYPE"
                local conflict_strategy="$DEFAULT_CONFLICT_STRATEGY"
            fi
            
            # Clean up whitespace
            source=$(echo "$source" | xargs)
            target=$(echo "$target" | xargs)

            # Check if it's a regex pattern (contains wildcards or capture groups)
            if [[ "$source" == *"("*")"* || "$source" == *"*"* || "$target" == *"\$"* ]]; then
                # Store in regex arrays
                SOURCE_REGEX+=("$source")
                TARGET_REGEX+=("$target")
                FILE_OPTIONS["regex:$source"]="link=$link_type conflict=$conflict_strategy"
            else
                # Store in direct mapping arrays
                SOURCE_TO_TARGET["$source"]="$target"
                FILE_OPTIONS["$source"]="link=$link_type conflict=$conflict_strategy"
            fi
            # debug "Stored mapping: $source => $SOURCE_TO_TARGET["$source"], link=$link_type, conflict=$conflict_strategy"
        fi
    done < "$config_path"
    REPO_PATH="${REPO_PATH/#\~/$HOME}"
    return 0
}
# Process regex-based mappings
process_regex_mappings() {
    echo -e "${BLUE}Processing regex-based mappings...${NC}"
    
    for i in "${!SOURCE_REGEX[@]}"; do
        local source_pattern="${SOURCE_REGEX[$i]}"
        local target_pattern="${TARGET_REGEX[$i]}"
        local options="${FILE_OPTIONS["regex:$source_pattern"]}"
        
        echo -e "${BLUE}Processing pattern: $source_pattern => $target_pattern${NC}"
        
        # Convert source_pattern to a glob pattern for finding files
        local glob_pattern="$REPO_PATH/${source_pattern//\(/*/}"
        glob_pattern="${glob_pattern//\)/}"
        
        # Find files matching the glob pattern
        local files=()
        while IFS= read -r -d $'\0' file; do
            files+=("$file")
        done < <(find "$REPO_PATH" -path "$glob_pattern" -print0 2>/dev/null)
        
        if [[ ${#files[@]} -eq 0 ]]; then
            echo -e "${YELLOW}No files matched pattern: $source_pattern${NC}"
            continue
        fi
        
        # Process each matching file
        for file in "${files[@]}"; do
            # Get relative path from repo root
            local rel_path="${file#$REPO_PATH/}"
            
            # Create target path by replacing capture groups
            local target="$target_pattern"
            
            # Extract capture groups from source pattern and file path
            if [[ "$source_pattern" == *"("*")"* && "$target_pattern" == *"\$"* ]]; then
                # Convert regex pattern to extended regex for bash
                local bash_regex="^${source_pattern//\(/\\(}$"
                bash_regex="${bash_regex//\)/\\)}"
                bash_regex="${bash_regex//\*/.*}"
                
                if [[ "$rel_path" =~ $bash_regex ]]; then
                    # Replace $1, $2, etc. with corresponding capture groups
                    for j in $(seq 1 ${#BASH_REMATCH[@]}); do
                        target="${target//\$$j/${BASH_REMATCH[$j]}}"
                    done
                fi
            elif [[ "$source_pattern" == *"*"* ]]; then
                # Simple wildcard replacement
                local prefix="${source_pattern%%\**}"
                local suffix="${source_pattern#*\*}"
                local middle="${rel_path#$prefix}"
                middle="${middle%$suffix}"
                
                target="${target_pattern/\*/$middle}"
            fi
            
            # Expand ~ in target path
            target="${target/#\~/$HOME}"
            
            echo -e "${GREEN}Matched: $rel_path => $target${NC}"
            
            # Sync the file
            sync_file "$rel_path" "$target" "$options"
        done
    done
}

# Process backward sync mappings
process_backward_sync() {
    echo -e "${BLUE}Processing backward sync mappings...${NC}"
    
    for mapping in "${BACKWARD_SYNC[@]}"; do
        # Parse the mapping
        local source="${mapping%% <= *}"
        local target="${mapping#* <= }"
        local options="${FILE_OPTIONS["$mapping"]}"
        
        echo -e "${BLUE}Processing backward sync: $source <= $target${NC}"
        
        # Expand ~ in paths
        source="${source/#\~/$HOME}"
        target="${target/#\~/$HOME}"
        
        # Check if target is a pattern
        if [[ "$target" == *"*"* ]]; then
            # Convert to glob pattern
            local glob_pattern="${target//\(/*/}"
            glob_pattern="${glob_pattern//\)/}"
            
            # Find files matching the glob pattern
            local files=()
            while IFS= read -r -d $'\0' file; do
                files+=("$file")
            done < <(find "${glob_pattern/#\~/$HOME}" -type f -print0 2>/dev/null)
            
            if [[ ${#files[@]} -eq 0 ]]; then
                echo -e "${YELLOW}No files matched backward pattern: $target${NC}"
                continue
            fi
            
            # Process each matching file
            for target_file in "${files[@]}"; do
                # Create source path based on target file
                local source_file="$source"
                
                if [[ "$source" == *"*"* && "$target" == *"*"* ]]; then
                    # Extract the wildcard part from target
                    local target_prefix="${target%%\**}"
                    local target_suffix="${target#*\*}"
                    local middle="${target_file#${target_prefix/#\~/$HOME}}"
                    middle="${middle%$target_suffix}"
                    
                    # Replace wildcard in source
                    source_file="${source/\*/$middle}"
                fi
                
                # Make sure source is relative to REPO_PATH
                if [[ "$source_file" == "$REPO_PATH"/* ]]; then
                    local rel_path="${source_file#$REPO_PATH/}"
                    source_file="$rel_path"
                elif [[ "$source_file" != /* ]]; then
                    source_file="$source_file"
                else
                    echo -e "${RED}Source must be relative to repo or an absolute path: $source_file${NC}"
                    continue
                fi
                
                echo -e "${GREEN}Backward sync: $source_file <= $target_file${NC}"
                
                # Sync from target to source
                backward_sync_file "$source_file" "$target_file" "$options"
            done
        else
            # Direct backward sync of a single file
            
            # Make sure source is relative to REPO_PATH
            if [[ "$source" == "$REPO_PATH"/* ]]; then
                local rel_path="${source#$REPO_PATH/}"
                source="$rel_path"
            elif [[ "$source" != /* ]]; then
                source="$source"
            else
                echo -e "${RED}Source must be relative to repo or an absolute path: $source${NC}"
                continue
            fi
            
            echo -e "${GREEN}Backward sync: $source <= $target${NC}"
            
            # Sync from target to source
            backward_sync_file "$source" "$target" "$options"
        fi
    done
}

# Backward sync a single file
backward_sync_file() {
    local source_rel="$1"
    local target="$2"
    local options="$3"
    
    # Extract options
    local link_type=$(echo "$options" | grep -o "link=[a-z]*" | cut -d= -f2)
    local conflict_strategy=$(echo "$options" | grep -o "conflict=[a-z]*" | cut -d= -f2)
    
    [[ -z "$link_type" ]] && link_type="$DEFAULT_LINK_TYPE"
    [[ -z "$conflict_strategy" ]] && conflict_strategy="$DEFAULT_CONFLICT_STRATEGY"
    
    # Convert relative source path to absolute
    local source="$REPO_PATH/$source_rel"
    
    # Expand ~ in target path
    target="${target/#\~/$HOME}"
    
    # Check if target exists
    if [[ ! -e "$target" ]]; then
        echo -e "${YELLOW}Target does not exist: $target${NC}"
        return 1
    fi
    
    # Create source directory if it doesn't exist
    mkdir -p "$(dirname "$source")"
    
    # Check if source exists
    if [[ -e "$source" ]]; then
        # Check if source is a symbolic link to the target:
        if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
            debug "Symbolic link already exists: $source"
            return 0
        fi

        # Check if they're different
        if diff -q "$source" "$target" &>/dev/null; then
            echo -e "${BLUE}Files are identical: $target${NC}"
            rm -rf "$target"
            ln -sf "$source" "$target"
            return 0
        else
            # Files are different - check modification times
            local source_mtime=$(stat -c %Y "$source" 2>/dev/null || stat -f %m "$source")
            local target_mtime=$(stat -c %Y "$target" 2>/dev/null || stat -f %m "$target")
            
            if [[ "$target_mtime" -gt "$source_mtime" ]]; then
                echo -e "${YELLOW}Target is newer than source: $target${NC}"
                # For backward sync, we typically want to update the source
                cp -rf "$target" "$source"
                echo -e "${GREEN}Updated source from target: $source_rel${NC}"
            else
                echo -e "${YELLOW}Source is newer than target: $source${NC}"
                handle_conflict "$source" "$target" "$conflict_strategy"
            fi
        fi
    else
        # Source doesn't exist - copy from target
        cp -rf "$target" "$source"
        echo -e "${GREEN}Created new source from target: $source_rel${NC}"
    fi
    
    return 0
}

# Create a link (hard or soft) between source and target
create_link() {
    local source="$1"
    local target="$2"
    local link_type="$3"
    
    # Ensure target directory exists
    local target_dir=$(dirname "$target")
    mkdir -p "$target_dir"
    
    if [[ "$link_type" == "hard" ]]; then
        ln "$source" "$target" && echo -e "${GREEN}Created hard link: $target -> $source${NC}"
    else
        ln -s "$source" "$target" && echo -e "${GREEN}Created symbolic link: $target -> $source${NC}"
    fi
    
    return $?
}

# Handle file conflicts based on strategy
handle_conflict() {
    local source="$1"
    local target="$2"
    local strategy="$3"
    
    case "$strategy" in
        "ask")
            echo -e "${YELLOW}Conflict detected:${NC}"
            echo "Source: $source"
            echo "Target: $target"
            echo -e "${YELLOW}What would you like to do?${NC}"
            echo "1) Keep local version (overwrite repository)"
            echo "2) Use repository version (overwrite local)"
            echo "3) Show diff"
            echo "4) Rename local and use repository version"
            echo "5) Ignore (keep both unchanged)"
            
            local choice
            read -p "Enter choice [1-5]: " choice
            
            case "$choice" in
                1) cp -rf "$target" "$source" ;;
                2) 
                    rm -rf $target
                    ln -s "$source" "$target" ;;
                3) 
                    diff -u "$target" "$source"
                    handle_conflict "$source" "$target" "ask"
                    ;;
                4) 
                    mv "$target" "${target}.backup.$(date +%Y%m%d%H%M%S)"
                    ln -s "$source" "$target"  #cp -rf "$source" "$target"
                    ;;
                5) echo "Ignoring conflict" ;;
                *) 
                    echo "Invalid choice"
                    handle_conflict "$source" "$target" "ask"
                    ;;
            esac
            ;;
        "local")
            cp -rf "$target" "$source"
            echo -e "${BLUE}Kept local version: $target${NC}"
            ;;
        "remote")
            # cp -rf "$source" "$target"
            rm -rf $target
            ln -s "$source" "$target" 
            echo -e "${BLUE}Used repository version: $source${NC}"
            ;;
        "rename")
            mv "$target" "${target}.backup.$(date +%Y%m%d%H%M%S)"
            # cp -rf "$source" "$target"
            ln -s "$source" "$target" 
            echo -e "${BLUE}Renamed local to ${target}.backup.* and used repository version${NC}"
            ;;
        "ignore")
            echo -e "${BLUE}Ignored conflict for: $target${NC}"
            ;;
        *)
            echo -e "${RED}Unknown conflict strategy: $strategy${NC}"
            handle_conflict "$source" "$target" "ask"
            ;;
    esac
    
    return 0
}

# Sync a single file/directory
sync_file() {
    local source_rel="$1"
    local target="$2"
    local options="$3"
    
    # Extract options
    local link_type=$(echo "$options" | grep -o "link=[a-z]*" | cut -d= -f2)
    local conflict_strategy=$(echo "$options" | grep -o "conflict=[a-z]*" | cut -d= -f2)
    
    [[ -z "$link_type" ]] && link_type="$DEFAULT_LINK_TYPE"
    [[ -z "$conflict_strategy" ]] && conflict_strategy="$DEFAULT_CONFLICT_STRATEGY"
    
    # Convert relative source path to absolute
    local source="$REPO_PATH/$source_rel"
    
    # Expand ~ in target path
    target="${target/#\~/$HOME}"
    
    # Check if source exists
    if [[ ! -e "$source" ]]; then
        if [[ -e "$target" ]]; then
            # Target exists but source doesn't - copy to repo
            echo -e "${BLUE}Found new dotfile: $target${NC}"
            mkdir -p "$(dirname "$source")"
            mv "$target" "$source"
            ln -sf "$source" "$target"
            echo -e "${GREEN}Added to repository: $source_rel${NC}"
        else
            echo -e "${RED}Neither source nor target exists: $source_rel${NC}"
            return 1
        fi
    fi
    
    # Check if target exists
    if [[ -e "$target" ]]; then
        # Check if it's a link pointing to our source
        if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
            # echo -e "${BLUE}Link already exists and is correct: $target${NC}"
            debug "Link already exists and is correct: $target"
            return 0
        fi
        
        # File exists but is not a correct link - check if it's different
        if diff -q "$source" "$target" &>/dev/null; then
            echo -e "${BLUE}Files are identical: $target${NC}"
            
            # If target is not a link to source, replace with link
            if [[ ! -L "$target" || "$(readlink "$target")" != "$source" ]]; then
                mv "$target" "${target}.backup.$(date +%Y%m%d%H%M%S)"
                create_link "$source" "$target" "$link_type"
            fi
        else
            # Files are different - check modification times
            local source_mtime=$(stat -c %Y "$source" 2>/dev/null || stat -f %m "$source")
            local target_mtime=$(stat -c %Y "$target" 2>/dev/null || stat -f %m "$target")
            
            if [[ "$target_mtime" -gt "$source_mtime" ]]; then
                echo -e "${YELLOW}Target is newer than source: $target${NC}"
                handle_conflict "$source" "$target" "$conflict_strategy"
            else
                echo -e "${YELLOW}Source is newer than target: $source${NC}"
                handle_conflict "$source" "$target" "$conflict_strategy"
            fi
        fi
    else
        # Target doesn't exist - create link
        create_link "$source" "$target" "$link_type"
    fi
    
    return 0
}

# Sync all dotfiles
sync_dotfiles() {
    echo -e "${BLUE}Syncing dotfiles...${NC}"

    debug "Syncing the following files: ${!SOURCE_TO_TARGET[@]}"
    for source in "${!SOURCE_TO_TARGET[@]}"; do
        debug "Syncing $source to ${SOURCE_TO_TARGET[$source]}"
        local target="${SOURCE_TO_TARGET[$source]}"
        local options="${FILE_OPTIONS[$source]}"
        
        sync_file "$source" "$target" "$options"
    done
    
    # Then, process regex-based mappings
    process_regex_mappings
    
    # Finally, process backward sync mappings
    process_backward_sync

    echo -e "${GREEN}Sync complete!${NC}"
    return 0
}

# Sync with git repository
git_sync() {
    local direction="$1" # push or pull
    local repo_path="$2"
    cd "$repo_path" || exit 1
    
    # Check if there are changes
    if [[ -n "$(git status --porcelain)" ]]; then
        echo -e "${BLUE}Changes detected in repository${NC}"
        git add .
        git commit -m "Auto-sync dotfiles $(date '+%Y-%m-%d %H:%M:%S')"
    fi
    
    if [[ "$direction" == "push" ]]; then
        if [[ -n "$REMOTE_URL" ]]; then
            # Check if remote is configured
            if ! git remote | grep -q origin; then
                git remote add origin "$REMOTE_URL"
            fi
            
            echo -e "${BLUE}Pushing changes to remote repository${NC}"
            git push origin master
        else
            echo -e "${YELLOW}No remote URL configured. Skipping push.${NC}"
        fi
    elif [[ "$direction" == "pull" ]]; then
        if [[ -n "$REMOTE_URL" ]]; then
            echo -e "${BLUE}Pulling changes from remote repository${NC}"
            
            # Check if remote is configured
            if ! git remote | grep -q origin; then
                git remote add origin "$REMOTE_URL"
            fi
            
            # Try to pull and merge
            if ! git pull origin master --ff-only; then
                echo -e "${YELLOW}Could not fast-forward merge. Trying to auto-merge...${NC}"
                
                if ! git pull origin master; then
                    echo -e "${RED}Merge conflict detected.${NC}"
                    
                    case "$DEFAULT_CONFLICT_STRATEGY" in
                        "ask")
                            echo -e "${YELLOW}How would you like to handle git conflicts?${NC}"
                            echo "1) Manual resolution (open editor)"
                            echo "2) Keep local changes"
                            echo "3) Use remote changes"
                            echo "4) Abort merge"
                            
                            local choice
                            read -p "Enter choice [1-4]: " choice
                            
                            case "$choice" in
                                1) git mergetool ;;
                                2) git reset --hard HEAD ;;
                                3) git reset --hard origin/master ;;
                                4) git merge --abort ;;
                                *) 
                                    echo "Invalid choice"
                                    git merge --abort
                                    ;;
                            esac
                            ;;
                        "local")
                            git reset --hard HEAD
                            ;;
                        "remote")
                            git reset --hard origin/master
                            ;;
                        "rename")
                            git merge --abort
                            
                            # Create backup branch
                            local backup_branch="backup-$(date +%Y%m%d%H%M%S)"
                            git branch "$backup_branch"
                            echo -e "${BLUE}Created backup branch: $backup_branch${NC}"
                            
                            # Force use remote
                            git reset --hard origin/master
                            ;;
                        "ignore")
                            git merge --abort
                            ;;
                        *)
                            git merge --abort
                            ;;
                    esac
                fi
            fi
        else
            echo -e "${YELLOW}No remote URL configured. Skipping pull.${NC}"
        fi
    fi
    
    return 0
}

# Add the script to bashrc if not already there
update_bashrc() {
    local script_path="$(realpath "$0")"
    local bashrc="$HOME/.bashrc"
    
    if ! grep -q "$script_path" "$bashrc"; then
        echo -e "${BLUE}Adding dotfiles synchronizer to .bashrc${NC}"
        
        cat >> "$bashrc" << EOL

# Dotfiles Synchronizer
if [ -f "$script_path" ] && [ "\$-" = *i* ]; then
    # Only run in interactive shells
    # Comment to disable auto-sync on shell startup:
    "$script_path" --dotfiles_sync --encrypted_sync --pull --push
    alias envsync="$script_path"
fi
EOL
        
        echo -e "${GREEN}Added to .bashrc. You can now use 'envsync' command.${NC}"
    else
        echo -e "${BLUE}Already added to .bashrc${NC}"
    fi
    
    return 0
}

# Main function
main() {
    local custom_config=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--config)
                custom_config="$2"
                shift 2
                ;;
            -r|--repo)
                REPO_PATH="$2"
                shift 2
                ;;
            -d|--dotfiles_sync)
                PERFORM_DOTFILES_SYNC=1
                shift
                ;;
            -e|--encrypted_sync)
                PERFORM_ENCRYPTED_SYNC=1
                shift
                ;;
            -p|--push)
                PERFORM_PUSH=1
                shift
                ;;
            -l|--pull)
                PERFORM_PULL=1
                shift
                ;;
            -i|--init)
                PERFORM_INIT=1
                shift
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set config file path
    [[ -z "$custom_config" ]] || CONFIG_FILE="$custom_config"
    
    # Initialize if requested
    if [[ -n "$PERFORM_INIT" ]]; then
        init_repo "$REPO_PATH"
        create_default_config "$CONFIG_FILE"
        update_bashrc
    fi
    
    # If no action specified, show help
    if [[ -z "$PERFORM_INIT" && -z "$PERFORM_PULL" && -z "$PERFORM_DOTFILES_SYNC" && -z "$PERFORM_ENCRYPTED_SYNC" && -z "$PERFORM_PUSH" ]]; then
        show_help
    fi
    
    # Load configuration
    load_config "$CONFIG_FILE"
    
    # TODO: depends on config OR flags,
    # TODO: if updated tell user the new version.

    # Perform actions
    [[ -n "$PERFORM_PULL" ]] && git_sync "pull" "$REPO_PATH"
    [[ -n "$PERFORM_ENCRYPTED_SYNC" ]] && sync_encrypted.sh
    [[ -n "$PERFORM_DOTFILES_SYNC" ]] && sync_dotfiles
    [[ -n "$PERFORM_PUSH" ]] && git_sync "push" "$REPO_PATH"
    
    return 0
}

# Start script
main "$@"