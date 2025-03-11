export ENV_LOC="/home/yashar/env" #
# "${ENV_LOC:-"$( cd "$( dirname "$( readlink -f "${0}" )" )" && pwd )"}"

# Load config

# If interactive:
# Git pull - depends on config, tell user the new version.
# Dotsync
# Git push

if [ -f "${ENV_LOC}/private/.secrets" ]; then
. ${ENV_LOC}/private/.secrets
fi

. ${ENV_LOC}/env
. ${ENV_LOC}/aliases

(duf &)
