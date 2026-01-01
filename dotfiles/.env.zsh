# Enable debug prints with: export ENV_DEBUG=1
if [[ "$ENV_DEBUG" == "1" ]]; then
    env_debug() { echo "[DEBUG] $*" >&2; }
else
    env_debug() { :; }
fi

ENV_DIR=$HOME/env
ENV_DIR="${ENV_DIR:-"$( dirname "$( dirname "$( readlink -f "${0}" )" )" )"}"

# Load config
env_debug "Loading config from ${ENV_DIR}/config/repo.conf"
source ${ENV_DIR}/config/repo.conf
env_debug "Loading env_vars from ${ENV_DIR}/env_vars"
source ${ENV_DIR}/env_vars

if [ -f "${ENV_DIR}/private/secrets" ]; then
    env_debug "Loading secrets from ${ENV_DIR}/private/secrets"
    . ${ENV_DIR}/private/secrets
#     echo "BW session is: $BW_SESSION"
# else
#     echo "Secrets was not found in "${ENV_DIR}/private/secrets""
fi

env_debug "Sourcing functions from ${ENV_DIR}/functions/*"
for file in ${ENV_DIR}/functions/*; do
  if [[ -f "$file" ]]; then
    env_debug "Sourcing $file"
    source "$file"
  fi
done

. ${ENV_DIR}/aliases
eval "$(zoxide init zsh)"

# If modified time of env is more than 1 day, check for updates
if [[ $- == *i* ]]; then
    env_debug "Interactive shell detected, running startup checks"
    local updates_detected_file="${ENV_DIR}/tmp/updates_detected"
    local lock_file="${ENV_DIR}/tmp/update_check.lock"

    if [ ! -f "${ENV_DIR}/tmp/updated" ] || [ "$(find "${ENV_DIR}/tmp/updated" -mtime +1 -print)" ]; then
        env_debug "Checking for env updates (background)"
        # Check for updates in background
        (
            flock -n 9 || exit 0  # Prevent concurrent checks
            env_debug "Update check: acquired lock, running sync_env.sh --check-updates"
            local update_status=$(${ENV_DIR}/scripts/sync_env.sh --check-updates)
            env_debug "Update check: status=$update_status"

            if [[ "$update_status" == "uncommitted" ]]; then
                echo "Uncommitted changes detected in env repo"
                touch "$updates_detected_file"
            elif [[ "$update_status" == "remote" ]]; then
                echo "Remote updates available for env repo"
                touch "$updates_detected_file"
            elif [[ "$update_status" == "none" ]]; then
                # No updates, touch the updated file
                touch "${ENV_DIR}/tmp/updated"
                # Remove updates_detected file if it exists
                rm -f "$updates_detected_file"
            fi
        ) 9>"$lock_file" &
    else
        env_debug "Update check skipped (updated file exists and is fresh)"
    fi

    # If updates have been available for more than 7 days, run full sync
    if [[ -f "$updates_detected_file" ]]; then
        local updates_age=$(( $(date +%s) - $(stat -c %Y "$updates_detected_file" 2>/dev/null || echo 0) ))
        local days_since_detected=$(( updates_age / 86400 ))
        env_debug "Updates detected $days_since_detected days ago"

        if [[ $days_since_detected -ge 7 ]]; then
            echo "Updates available for $days_since_detected days. Running full sync..."
            ${ENV_DIR}/scripts/sync_env.sh --encrypted_sync --dotfiles_sync --push --pull && touch ${ENV_DIR}/tmp/updated && rm -f "$updates_detected_file"
        else
            echo "Env updates available (detected $days_since_detected days ago). Run 'envsync' to sync."
        fi
    else
        env_debug "No pending updates detected"
    fi
    
    # title "Welcome"

    # # If mount file variable exists, then mount it
    # if [ -n "${MOUNT_FILE}" ]; then
    #     title "Mounting volumes..."
    #     mount -T ${MOUNT_FILE}
    # fi

    if [[ "$SHOW_DUFF" = "on" ]]; then
        env_debug "SHOW_DUFF=on, running duf in background"
        # echo "Running duf..."
        (duf &)
    else
        env_debug "SHOW_DUFF=off (set 'on' to enable)"
    fi

    if [[ "$SHOW_NEOFETCH" = "on" ]]; then
        env_debug "SHOW_NEOFETCH=on, running neofetch"
        neofetch
    else
        env_debug "SHOW_NEOFETCH=off (set 'on' to enable)"
    fi

    env_debug "Calling kuma_status"
    kuma_status;
    env_debug "Calling zerotier_clients"
    zerotier_clients;
    env_debug "Startup checks complete"
    
fi
