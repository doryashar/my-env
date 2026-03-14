# Enable debug prints with: export ENV_DEBUG=1
if [[ "$ENV_DEBUG" == "1" ]]; then
    env_debug() { echo "[DEBUG] $*" >&2; }
else
    env_debug() { :; }
fi

ENV_DIR="${ENV_DIR:-$HOME/env}"

# Helper function to get file age in days
file_age_days() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo 999999
        return
    fi
    local file_time
    file_time=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
    echo $(( ($(date +%s) - file_time) / 86400 ))
}

# Load config
env_debug "Loading config from ${ENV_DIR}/config/repo.conf"
if [[ -f "${ENV_DIR}/config/repo.conf" ]]; then
    source "${ENV_DIR}/config/repo.conf"
fi

env_debug "Loading env_vars from ${ENV_DIR}/env_vars"
if [[ -f "${ENV_DIR}/env_vars" ]]; then
    source "${ENV_DIR}/env_vars"
fi

# Load secrets if available
# Try symlink first (~/private -> ENV_DIR/tmp/private), then direct path
if [[ -f ~/private/secrets ]]; then
    env_debug "Loading secrets from ~/private/secrets"
    source ~/private/secrets
elif [[ -f "${ENV_DIR}/tmp/private/secrets" ]]; then
    env_debug "Loading secrets from ${ENV_DIR}/tmp/private/secrets"
    source "${ENV_DIR}/tmp/private/secrets"
else
    env_debug "No secrets file found (run setup.sh to sync encrypted files)"
fi

# Source functions
env_debug "Sourcing functions from ${ENV_DIR}/functions/*"
for file in "${ENV_DIR}"/functions/*; do
    if [[ -f "$file" ]]; then
        env_debug "Sourcing $file"
        source "$file"
    fi
done

# Load aliases
if [[ -f "${ENV_DIR}/aliases" ]]; then
    source "${ENV_DIR}/aliases"
fi

# Initialize zoxide
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi

# Interactive shell checks
if [[ $- == *i* ]]; then
    env_debug "Interactive shell detected"
    
    # Check for updates in background (silent, based on CHECK_INTERVAL_DAYS)
    check_interval="${CHECK_INTERVAL_DAYS:-1}"
    last_check_age=$(file_age_days "${ENV_DIR}/tmp/last_check")
    
    if [[ $last_check_age -ge $check_interval ]]; then
        env_debug "Running background update check (last check: $last_check_age days ago)"
        ( "${ENV_DIR}/scripts/sync_env.sh" --check-only 2>/dev/null ) &
    else
        env_debug "Skipping update check (last check: $last_check_age days ago)"
    fi
    
    # Prompt for sync if overdue (based on SYNC_INTERVAL_DAYS)
    sync_interval="${SYNC_INTERVAL_DAYS:-7}"
    last_sync_age=$(file_age_days "${ENV_DIR}/tmp/last_sync")
    
    if [[ $last_sync_age -ge $sync_interval ]]; then
        echo "Last sync was $last_sync_age days ago. Run 'envsync' to sync."
    else
        env_debug "Sync not needed (last sync: $last_sync_age days ago)"
    fi
    
    # Display utilities
    if [[ "$SHOW_DUFF" = "on" ]]; then
        env_debug "SHOW_DUFF=on, running duf in background"
        if command -v duf &>/dev/null; then
            (duf &)
        fi
    else
        env_debug "SHOW_DUFF=off (set 'on' to enable)"
    fi

    if [[ "$SHOW_NEOFETCH" = "on" ]]; then
        env_debug "SHOW_NEOFETCH=on, running neofetch"
        if command -v neofetch &>/dev/null; then
            neofetch
        fi
    else
        env_debug "SHOW_NEOFETCH=off (set 'on' to enable)"
    fi

    # Status checks
    if type kuma_status &>/dev/null; then
        env_debug "Calling kuma_status"
        kuma_status
    fi
    
    if type zerotier_clients &>/dev/null; then
        env_debug "Calling zerotier_clients"
        zerotier_clients
    fi
    
    env_debug "Startup checks complete"
fi
