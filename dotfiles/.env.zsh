
ENV_DIR=$HOME/env
ENV_DIR="${ENV_DIR:-"$( dirname "$( dirname "$( readlink -f "${0}" )" )" )"}"

# Load config
source ${ENV_DIR}/config/repo.conf
source ${ENV_DIR}/env_vars

if [ -f "${ENV_DIR}/private/secrets" ]; then
    . ${ENV_DIR}/private/secrets
#     echo "BW session is: $BW_SESSION"
# else
#     echo "Secrets was not found in "${ENV_DIR}/private/secrets""
fi

for file in ${ENV_DIR}/functions/*; do
  if [[ -f "$file" ]]; then
    source "$file"
  fi
done

. ${ENV_DIR}/aliases

# If modified time of env is more than  1 day, then update it and dotfiles
# if [ -t 0 ]; then
    if [ ! -f "${ENV_DIR}/tmp/updated" ] || [ "$(find "${ENV_DIR}/tmp/updated" -mtime +1 -print)" ]; then
        echo "Updating env..."
        ${ENV_DIR}/scripts/sync_env.sh --encrypted_sync --dotfiles_sync --push --pull && touch ${ENV_DIR}/tmp/updated
        #TODO: if updated run exec $0
    fi
    
    # title "Welcome"

    # # If mount file variable exists, then mount it
    # if [ -n "${MOUNT_FILE}" ]; then
    #     title "Mounting volumes..."
    #     mount -T ${MOUNT_FILE}
    # fi

    if [[ "$SHOW_DUFF" = "on" ]]; then
        # echo "Running duf..."
        (duf &)
    fi

    if [[ "$SHOW_NEOFETCH" = "on" ]]; then
        neofetch
    fi

# fi
