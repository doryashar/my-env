#!/bin/bash
#TODO: When linking a directory, dont link also the files inside it
#Why private/config/* does not match?

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
SELF_PATH="$(realpath "${BASH_SOURCE[0]}")"
ZERO_PATH="$(realpath "$0")"
ENV_DIR=${ENV_DIR:-$(dirname $(dirname "$SELF_PATH"))}
ENV_DIR=${ENV_DIR%/}

# Default configuration 
DEFAULT_LINK_TYPE="soft"
DEFAULT_CONFLICT_STRATEGY="ask"

# Parse the mapping lines
declare -A SOURCE_TO_TARGET
declare -A FILE_OPTIONS
SOURCE_REGEX=()
TARGET_REGEX=()
BACKWARD_SYNC=()

# # If ENV_DIR variable does not exist, source config:
# if [[ -z "$ENV_DIR" ]]; then
#     source "$ENV_DIR/config/env_vars"
#     # If ENV_DIR still does not exist, exit with an error
#     if [[ -z "$ENV_DIR" ]]; then
#         error "Failed to load configuration. Exiting."
#         exit 1
#     fi
# fi

# if function "title" does not exists, load common_funcs
if ! type -t title &> /dev/null; then
    source "$ENV_DIR/functions/common_funcs"
    title "Synchronizing Dotfiles${NC}"
fi

# Function to create default config file
create_default_config() {
    local config_path="$1"
    
    if [[ -f "$config_path" ]]; then
        warning "Config file already exists at $config_path"
        return 0
    fi
    
    info "Creating default configuration at $config_path"
    
    cat > "$config_path" << EOF
# Dotfiles Synchronizer Configuration

#########################################################################
# Global settings
#########################################################################

# Repository path (where dotfiles are stored in git)
# ENV_DIR="$ENV_DIR"

# Remote git repository URL (optional)
# REMOTE_URL=""

#TODO: Add sync option
# Default link type (soft or hard)
DEFAULT_LINK_TYPE="$DEFAULT_LINK_TYPE"

# Default conflict resolution strategy
# Options: ask, local, remote, rename, ignore
DEFAULT_CONFLICT_STRATEGY="$DEFAULT_CONFLICT_STRATEGY"


#########################################################################
# File mappings
# Format: SOURCE => TARGET  or  SOURCE <= TARGET
# 
# SOURCE paths are relative to ENV_DIR
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

    info "Default configuration created. Please edit $config_path to customize your setup."
    exit 0
}

# Parse and load configuration
load_config() {
    local config_path="$1"
    
    if [[ ! -f "$config_path" ]]; then
        warning "Config file not found at $config_path${NC}"
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
    ENV_DIR="${ENV_DIR/#\~/$HOME}"
    return 0
}

# Process regex-based mappings
process_regex_mappings() {
    debug "Processing regex-based mappings..."
    
    for i in "${!SOURCE_REGEX[@]}"; do
        local source_pattern="${SOURCE_REGEX[$i]}"
        local target_pattern="${TARGET_REGEX[$i]}"
        local options="${FILE_OPTIONS["regex:$source_pattern"]}"
        
        debug "Processing pattern: $source_pattern => $target_pattern"
        
        # Convert source_pattern to a glob pattern for finding files
        local glob_pattern="$ENV_DIR/${source_pattern//\(/*/}"
        glob_pattern="${glob_pattern//\)/}"
        
        # Find files matching the glob pattern
        local files=()
        while IFS= read -r -d $'\0' file; do
            files+=("$file")
        done < <(find "$ENV_DIR" -maxdepth $(($(printf '%s' "$source_pattern" | tr -cd '/' | wc -c) + 1)) -path $ENV_DIR/"$source_pattern" -print0 2>/dev/null)
        
        if [[ ${#files[@]} -eq 0 ]]; then
            warning "No files matched pattern: $source_pattern"
            continue
        fi
        
        # Process each matching file
        for file in "${files[@]}"; do
            # Get relative path from repo root
            local rel_path="${file#$ENV_DIR/}"
            
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
            
            debug "(-) Matched: $rel_path => $target"
            
            # Sync the file
            sync_file "$rel_path" "$target" "$options"
        done
    done
}

# Handle file conflicts based on strategy
handle_conflict() {
    local source="$1"
    local target="$2"
    local strategy="$3"
    
    case "$strategy" in
        "ask")
            warning "Conflict detected:"
            echo "Source: $source"
            echo "Target: $target"
            warning "What would you like to do?"
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
            info "Kept local version: $target"
            ;;
        "remote")
            # cp -rf "$source" "$target"
            rm -rf $target
            ln -s "$source" "$target" 
            info "Used repository version: $source${NC}"
            ;;
        "rename")
            mv "$target" "${target}.backup.$(date +%Y%m%d%H%M%S)"
            # cp -rf "$source" "$target"
            ln -s "$source" "$target" 
            info "Renamed local to ${target}.backup.* and used repository version${NC}"
            ;;
        "ignore")
            info "Ignored conflict for: $target${NC}"
            ;;
        *)
            error "Unknown conflict strategy: $strategy${NC}"
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
    local source="$ENV_DIR/$source_rel"
    
    # Expand ~ in target path
    target="${target/#\~/$HOME}"
    
    # Check if source exists
    if [[ ! -e "$source" ]]; then
        if [[ -e "$target" ]]; then
            # Target exists but source doesn't - copy to repo
            info "Found new dotfile: $target"
            mkdir -p "$(dirname "$source")"
            mv "$target" "$source"
            ln -sf "$source" "$target"
            info "Added to repository: $source_rel"
        else
            error "Neither source nor target exists: $source_rel"
            return 1
        fi
    fi
    
    # Check if target exists
    if [[ -e "$target" ]]; then
        # Check if it's a link pointing to our source
        if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
            debug "(-)(-) Link already exists and is correct: $target"
            return 0
        else
            if [[ -L "$target" ]]; then
                echo "link"
            fi
            if [[ "$(readlink "$target")" == "$source" ]]; then
                echo "same "$(readlink "$target")" $target $source"
            fi
        fi
        
        # File exists but is not a correct link - check if it's different
        if diff -q "$source" "$target" &>/dev/null; then
            debug "(-)(-) Files are identical: $target"
            
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
                warning "Target is newer than source: $target${NC}"
                handle_conflict "$source" "$target" "$conflict_strategy"
            else
                warning "Source is newer than target: $source${NC}"
                handle_conflict "$source" "$target" "$conflict_strategy"
            fi
        fi
    else
        # Target doesn't exist - create link
        debug "(-)(-) Creating link: $target"
        create_link "$source" "$target" "$link_type"
    fi
    
    return 0
}

# Process backward sync mappings
process_backward_sync() {
    debug "Processing backward sync mappings..."
    
    for mapping in "${BACKWARD_SYNC[@]}"; do
        # Parse the mapping
        local source="${mapping%% <= *}"
        local target="${mapping#* <= }"
        local options="${FILE_OPTIONS["$mapping"]}"
        
        debug "Processing backward sync: $source <= $target"
        
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
                warning "No files matched backward pattern: $target${NC}"
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
                
                # Make sure source is relative to ENV_DIR
                if [[ "$source_file" == "$ENV_DIR"/* ]]; then
                    local rel_path="${source_file#$ENV_DIR/}"
                    source_file="$rel_path"
                elif [[ "$source_file" != /* ]]; then
                    source_file="$source_file"
                else
                    error "Source must be relative to repo or an absolute path: $source_file"
                    continue
                fi
                
                debug "(-) Backward sync: $source_file <= $target_file${NC}"
                
                # Sync from target to source
                backward_sync_file "$source_file" "$target_file" "$options"
            done
        else
            # Direct backward sync of a single file
            
            # Make sure source is relative to ENV_DIR
            if [[ "$source" == "$ENV_DIR"/* ]]; then
                local rel_path="${source#$ENV_DIR/}"
                source="$rel_path"
            elif [[ "$source" != /* ]]; then
                source="$source"
            else
                error "Source must be relative to repo or an absolute path: $source"
                continue
            fi
            
            debug "(-) Backward sync: $source <= $target"
            
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
    local source="$ENV_DIR/$source_rel"
    
    # Expand ~ in target path
    target="${target/#\~/$HOME}"
    
    # Check if target exists
    if [[ ! -e "$target" ]]; then
        warning "Target does not exist: $target"
        return 1
    fi
    
    # Create source directory if it doesn't exist
    mkdir -p "$(dirname "$source")"
    
    # Check if source exists
    if [[ -e "$source" ]]; then
        # Check if source is a symbolic link to the target:
        if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
            debug "(-)(-) Symbolic link already exists: $source"
            return 0
        fi

        # Check if they're different
        if diff -q "$source" "$target" &>/dev/null; then
            debug "(-)(-) Files are identical: $target"
            rm -rf "$target"
            ln -sf "$source" "$target"
            return 0
        else
            # Files are different - check modification times
            local source_mtime=$(stat -c %Y "$source" 2>/dev/null || stat -f %m "$source")
            local target_mtime=$(stat -c %Y "$target" 2>/dev/null || stat -f %m "$target")
            
            if [[ "$target_mtime" -gt "$source_mtime" ]]; then
                warning "Target is newer than source: $target"
                # For backward sync, we typically want to update the source
                cp -rf "$target" "$source"
                info "Updated source from target: $source_rel"
            else
                warning "Source is newer than target: $source"
                handle_conflict "$source" "$target" "$conflict_strategy"
            fi
        fi
    else
        # Source doesn't exist - copy from target
        cp -rf "$target" "$source"
        info "Created new source from target: $source_rel"
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
    
    # if the broken link file exists, remove it
    if [[ -h "$target" ]]; then
        warning "Removing existing file (probably broken simlink): $target, $(ls -al "$target")"
        rm -rf "$target"
    fi

    if [[ "$link_type" == "hard" ]]; then
        ln "$source" "$target" && info "Created hard link: $target -> $source"
    else
        ln -s "$source" "$target" && info "Created symbolic link: $target -> $source"
    fi
    
    return $?
}

# Sync all dotfiles
sync_dotfiles() {
    debug "Syncing the following files: ${!SOURCE_TO_TARGET[@]}"
    for source in "${!SOURCE_TO_TARGET[@]}"; do
        debug "Forward Syncing $source to ${SOURCE_TO_TARGET[$source]}"
        local target="${SOURCE_TO_TARGET[$source]}"
        local options="${FILE_OPTIONS[$source]}"
        
        sync_file "$source" "$target" "$options"
    done
    
    # Then, process regex-based mappings
    process_regex_mappings
    
    # Finally, process backward sync mappings
    process_backward_sync

    debug "Sync complete!"
    return 0
}
remove_all_broken_links() {
    # list_files=$(find $directory -xtype l)
    directory="$1"
    find "$directory" -maxdepth 2 -type l | while read -r file; do
        if [[ -L "$file" ]] && [[ ! -e "$file" ]]; then
            warning "Removing broken symlink: $file"
            rm "$file"
        fi
    done
}
main() {
    if [[ "$#" -lt 1 ]]; then
        CONFIG_FILE="$ENV_DIR/config/dotfiles.conf"
    else
        CONFIG_FILE="$1"
    fi

    # Load configuration
    load_config "$CONFIG_FILE"
    
    # Sync dotfiles
    sync_dotfiles
    remove_all_broken_links $HOME
    return 0

}

if [[ "$SELF_PATH" == "$ZERO_PATH" ]]; then
    main $@
fi