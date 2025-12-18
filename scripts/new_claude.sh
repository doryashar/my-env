#!/usr/bin/env bash
set -euo pipefail

USE_CONTAINER=true
USE_DEVCONTAINER=false
USE_GLM=false
USE_BRANCH=false
CONTAINER_IMAGE="${CONTAINER_IMAGE:-docker/sandbox-templates:claude-code}"
DEVCONTAINER_IMAGE="anthropic-claude-devcontainer"
CLAUDE_CONFIG_DIR="${HOME}/.claude"

usage() {
  echo "Usage: $0 [--container] [--devcontainer] [--no_container] [--glm] [--branch] [branch-name]"
  echo "  --container        Use Docker sandbox template (docker/sandbox-templates:claude-code) (default)"
  echo "  --devcontainer     Use official Anthropic devcontainer (builds from Dockerfile)"
  echo "  --no_container     Use local Claude installation"
  echo "  --glm             Use GLM model instead of Claude"
  echo "  --branch          Create new branch instead of worktree"
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --container)
      USE_CONTAINER=true
      USE_DEVCONTAINER=false
      shift
      ;;
    --devcontainer)
      USE_DEVCONTAINER=true
      USE_CONTAINER=false
      shift
      ;;
    --no_container)
      USE_CONTAINER=false
      USE_DEVCONTAINER=false
      shift
      ;;
    --glm)
      USE_GLM=true
      shift
      ;;
    --branch)
      USE_BRANCH=true
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

# Set default branch name based on mode
if [ "$USE_BRANCH" = true ]; then
  BRANCH="${BRANCH:-br-$(date +%Y%m%d-%H%M%S)}"
else
  BRANCH="${BRANCH:-wt-$(date +%Y%m%d-%H%M%S)}"
fi

DIR=".worktrees/$BRANCH"

# Get repository root
REPO_ROOT=$(git rev-parse --show-toplevel)

# Get current branch as base
CURRENT_BRANCH=$(git branch --show-current || echo "HEAD")

if [ "$USE_BRANCH" = true ]; then
  echo ">>> Creating and checking out branch $BRANCH (based on $CURRENT_BRANCH)"
  git checkout -b "$BRANCH" "$CURRENT_BRANCH"

  # Cleanup function for branch mode
  cleanup() {
    echo ">>> Cleaning up branch $BRANCH"
    # Switch back to original branch
    git checkout "$CURRENT_BRANCH" 2>/dev/null || true
    # Delete the branch
    git branch -D "$BRANCH" 2>/dev/null || true
    echo ">>> Cleanup complete"
  }
  trap cleanup EXIT INT TERM
else
  mkdir -p .worktrees

  echo ">>> Creating worktree $DIR (branch: $BRANCH based on $CURRENT_BRANCH)"
  git worktree add "$DIR" -b "$BRANCH" "$CURRENT_BRANCH"

  # Cleanup function for worktree mode
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
fi

echo ">>> Repository root: $REPO_ROOT"

# Verify git remotes are accessible
if ! git remote -v &> /dev/null || [ -z "$(git remote)" ]; then
  echo ">>> Warning: No git remotes found"
fi



### Run Claude or GLM
# Determine which command to run
CLAUDE_COMMAND="claude"
if [ "$USE_GLM" = true ]; then
  CLAUDE_COMMAND="claude_glm"
fi

if [ "$USE_DEVCONTAINER" = true ]; then
  if [ "$USE_GLM" = true ]; then
    echo ">>> Running GLM in devcontainer"
  else
    echo ">>> Running Claude in devcontainer"
  fi

  # Check docker availability
  if ! command -v docker &> /dev/null; then
    echo "ERROR: docker command not found. Please install Docker or use --no_container flag"
    exit 1
  fi

  if ! docker info &> /dev/null; then
    echo "ERROR: Docker daemon is not running. Please start Docker or use --no_container flag"
    exit 1
  fi

  # Build devcontainer image if it doesn't exist
  if ! docker image inspect "$DEVCONTAINER_IMAGE" &> /dev/null; then
    echo ">>> Building devcontainer image from official Dockerfile"

    # Create temporary directory for build context
    BUILD_DIR=$(mktemp -d)
    trap "rm -rf $BUILD_DIR" EXIT

    # Fetch Dockerfile and init-firewall.sh
    echo ">>> Downloading Dockerfile and init-firewall.sh"
    curl -sL https://raw.githubusercontent.com/anthropics/claude-code/main/.devcontainer/Dockerfile -o "$BUILD_DIR/Dockerfile"
    curl -sL https://raw.githubusercontent.com/anthropics/claude-code/main/.devcontainer/init-firewall.sh -o "$BUILD_DIR/init-firewall.sh"

    # Get local Claude version to match
    LOCAL_CLAUDE_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "latest")
    echo ">>> Local Claude version: $LOCAL_CLAUDE_VERSION"

    # Build image with matching Claude version
    echo ">>> Building Docker image (this may take a few minutes)"
    docker build --build-arg CLAUDE_CODE_VERSION="$LOCAL_CLAUDE_VERSION" -t "$DEVCONTAINER_IMAGE" "$BUILD_DIR"
  fi

  # Use persistent volume for container-specific credentials
  # Following the approach from https://github.com/nociza/cuti
  # Container needs its own Linux-specific credentials, can't share host credentials
  CLAUDE_CONTAINER_VOLUME="claude-devcontainer-config"

  echo ">>> Using persistent Claude config volume: $CLAUDE_CONTAINER_VOLUME"

  # Check if this is first run (volume is empty)
  VOLUME_EXISTS=$(docker volume ls -q -f name="^${CLAUDE_CONTAINER_VOLUME}$")
  if [ -z "$VOLUME_EXISTS" ]; then
    echo ">>> First run: Creating persistent credentials volume"
    echo ">>> IMPORTANT: You'll need to complete Claude onboarding:"
    echo ">>>   1. Select your preferred theme"
    echo ">>>   2. Complete authentication (browser will open)"
    echo ">>> Your credentials will persist across all worktree sessions"

    # Create volume and set correct permissions
    docker volume create "$CLAUDE_CONTAINER_VOLUME" > /dev/null
    docker run --rm --user root \
      -v "$CLAUDE_CONTAINER_VOLUME:/home/node/.claude" \
      "$DEVCONTAINER_IMAGE" \
      sh -c "chown -R node:node /home/node/.claude && chmod 700 /home/node/.claude"
  else
    echo ">>> Using existing credentials from persistent volume"
  fi

  # Prepare environment variables
  ENV_VARS=("-e" "CLAUDE_CONFIG_DIR=/home/node/.claude")

  # Pass GitHub token if available and configure git credential helper
  if [ -n "${GITHUB_API_TOKEN:-}" ]; then
    ENV_VARS+=("-e" "GH_TOKEN=$GITHUB_API_TOKEN")
    ENV_VARS+=("-e" "GITHUB_TOKEN=$GITHUB_API_TOKEN")
    echo ">>> Passing GitHub token as GH_TOKEN"
  fi

  # Run Claude/GLM in devcontainer with persistent volume
  docker run --rm -it \
    -v "$(pwd):/workspace" \
    -v "$REPO_ROOT/.git:$REPO_ROOT/.git" \
    -v "$CLAUDE_CONTAINER_VOLUME:/home/node/.claude" \
    -w /workspace \
    "${ENV_VARS[@]}" \
    --user node \
    --entrypoint /bin/bash \
    "$DEVCONTAINER_IMAGE" \
    -c "if [ -n \"\$GITHUB_TOKEN\" ]; then git config --global credential.helper \"!f() { echo username=git; echo password=\$GITHUB_TOKEN; }; f\"; fi && exec $CLAUDE_COMMAND --dangerously-skip-permissions"

elif [ "$USE_CONTAINER" = true ]; then
  if [ "$USE_GLM" = true ]; then
    echo ">>> Running GLM in container: $CONTAINER_IMAGE"
  else
    echo ">>> Running Claude in container: $CONTAINER_IMAGE"
  fi

  # Check docker availability
  if ! command -v docker &> /dev/null; then
    echo "ERROR: docker command not found. Please install Docker or use --no_container flag"
    exit 1
  fi

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

  # Use persistent volume for container-specific credentials
  # Following the approach from https://github.com/nociza/cuti
  CLAUDE_CONTAINER_VOLUME="claude-sandbox-config"

  echo ">>> Using persistent Claude config volume: $CLAUDE_CONTAINER_VOLUME"

  # Check if this is first run (volume is empty)
  VOLUME_EXISTS=$(docker volume ls -q -f name="^${CLAUDE_CONTAINER_VOLUME}$")
  if [ -z "$VOLUME_EXISTS" ]; then
    echo ">>> First run: Creating persistent credentials volume"
    echo ">>> IMPORTANT: You'll need to complete Claude onboarding:"
    echo ">>>   1. Select your preferred theme"
    echo ">>>   2. Complete authentication (browser will open)"
    echo ">>> Your credentials will persist across all worktree sessions"

    # Create volume and set correct permissions
    docker volume create "$CLAUDE_CONTAINER_VOLUME" > /dev/null
    docker run --rm --user root \
      -v "$CLAUDE_CONTAINER_VOLUME:/home/agent/.claude" \
      "$CONTAINER_IMAGE" \
      sh -c "chown -R agent:agent /home/agent/.claude && chmod 700 /home/agent/.claude"
  else
    echo ">>> Using existing credentials from persistent volume"
  fi

  # Prepare environment variables
  ENV_VARS=("-e" "CLAUDE_CONFIG_DIR=/home/agent/.claude")

  # Pass GitHub token if available and configure git credential helper
  if [ -n "${GITHUB_API_TOKEN:-}" ]; then
    ENV_VARS+=("-e" "GH_TOKEN=$GITHUB_API_TOKEN")
    ENV_VARS+=("-e" "GITHUB_TOKEN=$GITHUB_API_TOKEN")
    echo ">>> Passing GitHub token as GH_TOKEN"
  fi

  # Run Claude/GLM in sandbox container with persistent volume
  docker run --rm -it \
    -v "$(pwd):/workspace" \
    -v "$REPO_ROOT/.git:$REPO_ROOT/.git" \
    -v "$CLAUDE_CONTAINER_VOLUME:/home/agent/.claude" \
    -w /workspace \
    "${ENV_VARS[@]}" \
    --entrypoint /bin/bash \
    "$CONTAINER_IMAGE" \
    -c "if [ -n \"\$GITHUB_TOKEN\" ]; then git config --global credential.helper \"!f() { echo username=git; echo password=\$GITHUB_TOKEN; }; f\"; fi && exec $CLAUDE_COMMAND --dangerously-skip-permissions"

else
  if [ "$USE_GLM" = true ]; then
    echo ">>> Running GLM locally"
    claude_glm --dangerously-skip-permissions
  else
    echo ">>> Running Claude locally"
    claude --dangerously-skip-permissions
  fi
fi

