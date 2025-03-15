export ENV_LOC="/home/yashar/env" #
# "${ENV_LOC:-"$( cd "$( dirname "$( readlink -f "${0}" )" )" && pwd )"}"

# Load config
# If modified time of env is more than  1 day, then update it and dotfiles
if [ ! -f "${ENV_LOC}/tmp/updated" ] || [ "$(find "${ENV_LOC}/tmp/updated" -mtime +1 -print)" ]; then
    echo "Updating env..."
    ${ENV_LOC}/scripts/sync_env.sh --encrypted_sync --dotfiles_sync --push --pull && touch ${ENV_LOC}/tmp/updated
fi

if [ -f "${ENV_LOC}/private/.secrets" ]; then
. ${ENV_LOC}/private/.secrets
fi

. ${ENV_LOC}/env
. ${ENV_LOC}/functions/*
. ${ENV_LOC}/aliases

echo "Running duf..."
(duf &)
