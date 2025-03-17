export ENV_LOC="/home/yashar/env" #
# "${ENV_LOC:-"$( cd "$( dirname "$( readlink -f "${0}" )" )" && pwd )"}"

# Load config
. ${ENV_LOC}/env

if [ -f "${ENV_LOC}/private/secrets" ]; then
. ${ENV_LOC}/private/secrets
fi

. ${ENV_LOC}/functions/*
. ${ENV_LOC}/aliases

# If modified time of env is more than  1 day, then update it and dotfiles
if [ -t 0 ]; then
    if [ ! -f "${ENV_LOC}/tmp/updated" ] || [ "$(find "${ENV_LOC}/tmp/updated" -mtime +1 -print)" ]; then
        echo "Updating env..."
        ${ENV_LOC}/scripts/sync_env.sh --encrypted_sync --dotfiles_sync --push --pull && touch ${ENV_LOC}/tmp/updated
        #TODO: if updated run exec $0
    fi
fi

# If mount file variable exists, then mount it
if [ -n "${MOUNT_FILE}" ]; then
    title "Mounting volumes..."
    mount -T ${MOUNT_FILE}
fi

<<<<<<< HEAD
=======
. ${ENV_LOC}/env_vars
. ${ENV_LOC}/functions/*
. ${ENV_LOC}/aliases

>>>>>>> Auto-sync dotfiles 2025-03-17 12:30:23
echo "Running duf..."
(duf &)
