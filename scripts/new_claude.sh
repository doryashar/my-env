#!/usr/bin/env bash
set -euo pipefail

USE_CONTAINER=false
CONTAINER_IMAGE="${CONTAINER_IMAGE:-docker/sandbox-templates:claude-code}"
CLAUDE_CONFIG_DIR="${HOME}/.claude"

usage() {
  echo "Usage: $0 [--container] [--no_container] [branch-name]"
  echo "  --container       Use containerized Claude (requires CONTAINER_IMAGE env var)"
  echo "  --no_container    Use local Claude installation (default)"
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --container)
      USE_CONTAINER=true
      shift
      ;;
    --no_container)
      USE_CONTAINER=false
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      BRANCH="$1"
      shift
      ;;
  esac
done

BRANCH="${BRANCH:-wt-$(date +%Y%m%d-%H%M%S)}"
DIR=".worktrees/$BRANCH"

mkdir -p .worktrees

# Get current branch as base for new worktree
CURRENT_BRANCH=$(git branch --show-current || echo "HEAD")

echo ">>> Creating worktree $DIR (branch: $BRANCH based on $CURRENT_BRANCH)"
git worktree add "$DIR" -b "$BRANCH" "$CURRENT_BRANCH"

# Cleanup function (runs on exit or Ctrl-C)
cleanup() {
  echo ">>> Cleaning up worktree $DIR"

  # Remove worktree
  git worktree remove "$DIR" --force || true

  # Delete branch
  git branch -D "$BRANCH" 2>/dev/null || true

  # Delete directory if still exists
  rm -rf "$DIR" || true

  echo ">>> Cleanup complete"
}
trap cleanup EXIT INT TERM

cd "$DIR"
echo ">>> Entered $DIR"



### Run Claude
if [ "$USE_CONTAINER" = true ]; then
  echo ">>> Running Claude in container: $CONTAINER_IMAGE"

  # Check if docker is available
  if ! command -v docker &> /dev/null; then
    echo "ERROR: docker command not found. Please install Docker or use --no_container flag"
    exit 1
  fi

  # Check if docker daemon is running
  if ! docker info &> /dev/null; then
    echo "ERROR: Docker daemon is not running. Please start Docker or use --no_container flag"
    exit 1
  fi

  # Pull image if not present
  if ! docker image inspect "$CONTAINER_IMAGE" &> /dev/null; then
    echo ">>> Pulling container image: $CONTAINER_IMAGE"
    if ! docker pull "$CONTAINER_IMAGE"; then
      echo "ERROR: Failed to pull container image: $CONTAINER_IMAGE"
      echo "Please either:"
      echo "  1. Set CONTAINER_IMAGE to a valid Docker image"
      echo "  2. Use --no_container to run Claude locally"
      exit 1
    fi
  fi

  # Mounts for workspace and credentials
  MOUNTS=(
    "-v" "$(pwd)":/workspace
    "-w" /workspace
  )

  # Mount Claude config directory if it exists
  if [ -d "$CLAUDE_CONFIG_DIR" ]; then
    echo ">>> Mounting Claude config from $CLAUDE_CONFIG_DIR"
    MOUNTS+=("-v" "$CLAUDE_CONFIG_DIR:/home/agent/.claude")

    # Disable Docker sandbox credential management to use mounted credentials
    docker run --rm -it "${MOUNTS[@]}" \
      -e "DOCKER_SANDBOX_CREDENTIALS=none" \
      "$CONTAINER_IMAGE" \
      claude --dangerously-skip-permissions
  else
    echo ">>> No local credentials found at $CLAUDE_CONFIG_DIR"
    docker run --rm -it "${MOUNTS[@]}" "$CONTAINER_IMAGE"
  fi

else
  echo ">>> Running Claude locally"
  claude --dangerously-skip-permissions
fi

