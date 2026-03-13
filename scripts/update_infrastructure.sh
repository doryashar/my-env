#!/bin/bash
set -euo pipefail

#########################################################################
# Update Infrastructure Script
#########################################################################
# Updates infrastructure scripts from upstream repository.
# This allows users to fork the repo and still get updates to the
# framework scripts without losing their customizations.
#
# Usage:
#   ./update_infrastructure.sh [--dry-run]
#
# Config (config/repo.conf):
#   UPSTREAM_URL - URL of upstream repository (default: doryashar/my-env)
#########################################################################

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
ENV_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# Prompt for y/n (works even when stdin is piped)
prompt_yn() {
    local question="$1"
    local reply
    if [[ -t 0 ]]; then
        read -p "$question" -n 1 -r
        echo
    else
        echo -n "$question"
        read -r reply < /dev/tty
        REPLY="${reply:0:1}"
    fi
    [[ "$REPLY" =~ ^[Yy]$ ]]
}

# Default upstream URL
DEFAULT_UPSTREAM_URL="git@github.com:doryashar/my-env.git"

# Load config if available
if [[ -f "$ENV_DIR/config/repo.conf" ]]; then
    source "$ENV_DIR/config/repo.conf"
fi

UPSTREAM_URL="${UPSTREAM_URL:-$DEFAULT_UPSTREAM_URL}"
DRY_RUN="${1:-}"

# Infrastructure files to update (never touch user configs)
INFRA_FILES=(
    "scripts/setup.sh"
    "scripts/sync_env.sh"
    "scripts/sync_dotfiles.sh"
    "scripts/sync_encrypted.sh"
    "scripts/install_docker.sh"
    "scripts/install_fonts.sh"
    "functions/common_funcs"
    "functions/helpers"
)

info "Fetching updates from upstream..."
info "Upstream: $UPSTREAM_URL"

# Create a temp ref for upstream master
UPSTREAM_REF="upstream-temp-$$"

cleanup() {
    git update-ref -d "$UPSTREAM_REF" 2>/dev/null || true
}
trap cleanup EXIT

# Fetch upstream without affecting local branches
if ! git fetch "$UPSTREAM_URL" master:refs/"$UPSTREAM_REF" 2>&1; then
    error "Failed to fetch from upstream. Check UPSTREAM_URL in config/repo.conf"
fi

# Check if there are any changes
LOCAL_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")
UPSTREAM_COMMIT=$(git rev-parse "$UPSTREAM_REF" 2>/dev/null || echo "")

if [[ "$LOCAL_COMMIT" == "$UPSTREAM_COMMIT" ]]; then
    info "Already up to date with upstream"
    exit 0
fi

info "Updates available from upstream"
echo ""
echo "Changed infrastructure files:"
echo "-----------------------------"

CHANGES_FOUND=0
for file in "${INFRA_FILES[@]}"; do
    if git diff --quiet "$LOCAL_COMMIT" "$UPSTREAM_REF" -- "$file" 2>/dev/null; then
        continue
    fi
    CHANGES_FOUND=1
    echo "  - $file"
done

if [[ "$CHANGES_FOUND" == "0" ]]; then
    info "No infrastructure file changes detected"
    exit 0
fi

# Dry run mode
if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo ""
    info "Dry run mode - no changes made"
    exit 0
fi

echo ""
if prompt_yn "Apply these updates? [y/N] "; then
    :  # continue
else
    info "Aborted"
    exit 0
fi

# Apply updates
info "Applying infrastructure updates..."
UPDATED_COUNT=0

for file in "${INFRA_FILES[@]}"; do
    # Check if file exists in upstream
    if ! git cat-file -e "$UPSTREAM_REF:$file" 2>/dev/null; then
        continue
    fi
    
    # Create directory if needed
    dir="$(dirname "$ENV_DIR/$file")"
    mkdir -p "$dir"
    
    # Extract file from upstream
    if git show "$UPSTREAM_REF:$file" > "$ENV_DIR/$file" 2>/dev/null; then
        ((UPDATED_COUNT++)) || UPDATED_COUNT=$((UPDATED_COUNT + 1))
        echo "  Updated: $file"
    fi
done

info "Updated $UPDATED_COUNT infrastructure files"
info "Your config files and customizations were preserved"
