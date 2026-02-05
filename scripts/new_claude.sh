#!/usr/bin/env bash
set -euo pipefail

USE_CONTAINER=true
USE_DEVCONTAINER=false
USE_GLM=false
USE_BRANCH=false
INSTALL_REQUIREMENTS=false
USE_VENV=true
CONTAINER_IMAGE="${CONTAINER_IMAGE:-docker/sandbox-templates:claude-code}"
DEVCONTAINER_IMAGE="anthropic-claude-devcontainer"
CLAUDE_CONFIG_DIR="${HOME}/.claude"

# Source shared virtualenv functions
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ENV_DIR=$(dirname "$SCRIPT_DIR")
source "$ENV_DIR/functions/virtualenv.sh"

usage() {
  echo "Usage: $0 [--container] [--devcontainer] [--no_container] [--glm] [--branch] [--install_requirements] [--no-venv] [branch-name]"
  echo "  --container        Use Docker sandbox template (docker/sandbox-templates:claude-code) (default)"
  echo "  --devcontainer     Use official Anthropic devcontainer (builds from Dockerfile)"
  echo "  --no_container     Use local Claude installation"
  echo "  --glm             Use GLM model instead of Claude"
  echo "  --branch          Create new branch instead of worktree"
  echo "  --install_requirements  Install repository requirements when loading container"
  echo "  --no-venv         Disable virtual environment activation in container"
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
    --install_requirements)
      INSTALL_REQUIREMENTS=true
      shift
      ;;
    --no-venv)
      USE_VENV=false
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

# Helper functions to reduce code duplication

# Build GLM environment variables
build_glm_env_vars() {
  if [ "$USE_GLM" = true ]; then
    cat << EOF
export ANTHROPIC_AUTH_TOKEN="\$GLM_API_KEY"
export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
export API_TIMEOUT_MS="3000000"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-4.5-air"
export ANTHROPIC_DEFAULT_SONNET_MODEL="glm-4.6"
export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-4.6"
EOF
  fi
}

# Build the container command string
build_container_command() {
  local install_cmd=""
  if [ "$INSTALL_REQUIREMENTS" = true ]; then
    install_cmd="install_requirements && "
  fi

  # Output the virtualenv functions (from shared file)
  cat "$ENV_DIR/functions/virtualenv.sh"

  echo ""

  # Output git credential helper setup
  cat << 'EOF'

if [ -n "$GITHUB_TOKEN" ]; then
  git config --global credential.helper "!f() { echo username=git; echo password=\$GITHUB_TOKEN; }; f"
fi

EOF

  # Add GLM environment variables if needed
  build_glm_env_vars

  # Add the final command
  cat << EOF
detect_and_activate_venv && ${install_cmd}exec claude --dangerously-skip-permissions
EOF
}

# Setup docker volume and permissions (now uses host mount instead of separate volume)
setup_docker_volume() {
  local claude_home="$1"

  echo ">>> Using host Claude config directory: $HOME/.claude -> $claude_home"

  # Ensure host .claude directory exists
  if [ ! -d "$HOME/.claude" ]; then
    echo ">>> Creating host .claude directory: $HOME/.claude"
    mkdir -p "$HOME/.claude"
    chmod 700 "$HOME/.claude"
  fi
}

# Prepare environment variables for docker
prepare_env_vars() {
  local claude_home="$1"
  local env_vars=("-e" "CLAUDE_CONFIG_DIR=$claude_home")

  # Pass GLM API key if using GLM
  if [ "$USE_GLM" = true ] && [ -n "${GLM_API_KEY:-}" ]; then
    env_vars+=("-e" "GLM_API_KEY=$GLM_API_KEY")
  fi

  # Pass GitHub token if available
  if [ -n "${GITHUB_API_TOKEN:-}" ]; then
    env_vars+=("-e" "GH_TOKEN=$GITHUB_API_TOKEN")
    env_vars+=("-e" "GITHUB_TOKEN=$GITHUB_API_TOKEN")
  fi

  # Pass virtual environment preference
  env_vars+=("-e" "USE_VENV=$USE_VENV")

  # Return the array
  printf '%s\n' "${env_vars[@]}"
}

# Check docker availability
check_docker() {
  if ! command -v docker &> /dev/null; then
    echo "ERROR: docker command not found. Please install Docker or use --no_container flag"
    exit 1
  fi

  if ! docker info &> /dev/null; then
    echo "ERROR: Docker daemon is not running. Please start Docker or use --no_container flag"
    exit 1
  fi
}

# Setup GLM environment locally
setup_local_glm() {
  if [ "$USE_GLM" = true ]; then
    export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"
    export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
    export API_TIMEOUT_MS="3000000"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-4.5-air"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="glm-4.6"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-4.6"
  fi
}

# Run docker container with unified logic
run_docker_container() {
  local image="$1"
  local user="$2"
  local claude_home="$3"
  local extra_args=()

  # Add user flag if specified
  if [ -n "$user" ]; then
    extra_args+=("--user" "$user")
  fi

  # Check and setup docker
  check_docker

  # Build the container command
  local cmd
  cmd=$(build_container_command)

  # Setup host mount for .claude directory
  setup_docker_volume "$claude_home"

  # Prepare environment variables and provide feedback
  local env_vars
  readarray -t env_vars < <(prepare_env_vars "$claude_home")

  # Provide user feedback for what's being passed
  if [ "$USE_GLM" = true ] && [ -n "${GLM_API_KEY:-}" ]; then
    echo ">>> Passing GLM API key"
  fi
  if [ -n "${GITHUB_API_TOKEN:-}" ]; then
    echo ">>> Passing GitHub token as GH_TOKEN"
  fi

  # Run the container with host .claude directory mounted
  docker run --rm -it \
    -v "$REPO_ROOT:/workspace" \
    -v "$HOME/.claude:$claude_home" \
    -w "/workspace/$RELATIVE_PATH" \
    "${env_vars[@]}" \
    "${extra_args[@]}" \
    --entrypoint /bin/bash \
    "$image" \
    -c "$cmd"
}

# Early validation: Check for GLM_API_KEY before any git operations
if [ "$USE_GLM" = true ] && [ -z "${GLM_API_KEY:-}" ]; then
  echo "ERROR: GLM_API_KEY not set. Please set it to use GLM mode."
  echo "Example: export GLM_API_KEY='your-api-key-here'"
  exit 1
fi

# Get repository root and save current directory
REPO_ROOT=$(git rev-parse --show-toplevel) || {
  echo "ERROR: Not in a git repository" >&2
  exit 1
}
ORIGINAL_DIR=$(pwd)

# Set worktree directory path after REPO_ROOT is defined
DIR="$REPO_ROOT/.worktrees/$BRANCH"

# Calculate relative path from repo root to current directory
if [ "$ORIGINAL_DIR" = "$REPO_ROOT" ]; then
  RELATIVE_PATH="."
else
  RELATIVE_PATH="${ORIGINAL_DIR#$REPO_ROOT/}"
fi

# Get current branch as base
CURRENT_BRANCH=$(git branch --show-current || echo "HEAD")

if [ "$USE_BRANCH" = true ]; then
  # Create the worktrees directory at the repository root level
  mkdir -p "$REPO_ROOT/.worktrees"

  # Create a clean directory for the branch
  echo ">>> Creating clean directory for branch $BRANCH in $DIR"

  # Save original repo root before we change it
  ORIGINAL_REPO_ROOT="$REPO_ROOT"

  # Use rsync to copy everything except .worktrees to avoid recursion
  rsync -av --exclude='.worktrees' --exclude='.git' "$ORIGINAL_REPO_ROOT/" "$DIR/"

  # Copy .git separately
  cp -r "$ORIGINAL_REPO_ROOT/.git" "$DIR/"

  # Enter the new directory and create the branch
  cd "$DIR"
  echo ">>> Entered $DIR"

  # Initialize as a separate git repo and create the branch
  git checkout -b "$BRANCH" "$CURRENT_BRANCH"
  echo ">>> Created branch $BRANCH (based on $CURRENT_BRANCH) in clean directory"

  # Update REPO_ROOT to point to the branch directory for container mounts
  REPO_ROOT="$DIR"

  # Cleanup function for branch mode
  cleanup() {
    # Clean up any temporary build directory
    if [[ -n "${BUILD_DIR:-}" ]] && [[ -d "$BUILD_DIR" ]]; then
      rm -rf "$BUILD_DIR"
    fi
    echo ">>> Cleaning up branch $BRANCH in $DIR"
    # Go back to original directory
    cd "$REPO_ROOT/$RELATIVE_PATH" 2>/dev/null || cd "$ORIGINAL_DIR" 2>/dev/null || cd "$REPO_ROOT"
    # Delete the directory
    rm -rf "$DIR" || true
    echo ">>> Cleanup complete"
  }
  trap cleanup EXIT INT TERM
else
  mkdir -p .worktrees

  echo ">>> Creating worktree $DIR (branch: $BRANCH based on $CURRENT_BRANCH)"
  git worktree add "$DIR" -b "$BRANCH" "$CURRENT_BRANCH"

  # Cleanup function for worktree mode
  cleanup() {
    # Clean up any temporary build directory
    if [[ -n "${BUILD_DIR:-}" ]] && [[ -d "$BUILD_DIR" ]]; then
      rm -rf "$BUILD_DIR"
    fi
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

if [ "$USE_DEVCONTAINER" = true ]; then
  if [ "$USE_GLM" = true ]; then
    echo ">>> Running GLM in devcontainer"
  else
    echo ">>> Running Claude in devcontainer"
  fi

  # Build devcontainer image if it doesn't exist
  if ! docker image inspect "$DEVCONTAINER_IMAGE" &> /dev/null; then
    echo ">>> Building devcontainer image from official Dockerfile"

    # Create temporary directory for build context
    BUILD_DIR=$(mktemp -d)
    # BUILD_DIR will be cleaned up by the main cleanup function

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

  # Run the devcontainer with our unified function
  run_docker_container "$DEVCONTAINER_IMAGE" "node" "/home/node/.claude"

elif [ "$USE_CONTAINER" = true ]; then
  if [ "$USE_GLM" = true ]; then
    echo ">>> Running GLM in container: $CONTAINER_IMAGE"
  else
    echo ">>> Running Claude in container: $CONTAINER_IMAGE"
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

  # Run the container with our unified function
  run_docker_container "$CONTAINER_IMAGE" "agent" "/home/agent/.claude"

else
  if [ "$USE_GLM" = true ]; then
    echo ">>> Running GLM locally"
  else
    echo ">>> Running Claude locally"
  fi

  # Setup GLM environment if needed
  setup_local_glm

  # Activate virtual environment and install requirements if requested
  if [ "$INSTALL_REQUIREMENTS" = true ] || [ "$USE_VENV" = true ]; then
    detect_and_activate_venv
  fi
  if [ "$INSTALL_REQUIREMENTS" = true ]; then
    install_requirements
  fi

  claude --dangerously-skip-permissions
fi

