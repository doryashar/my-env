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

DIR="$REPO_ROOT/.worktrees/$BRANCH"

install_requirements() {
  echo ">>> Installing repository requirements..."

  # Python requirements
  if [ -f "requirements.txt" ]; then
    echo ">>> Installing Python requirements from requirements.txt"
    pip install -r requirements.txt
  fi

  if [ -f "pyproject.toml" ]; then
    echo ">>> Installing Python package from pyproject.toml"
    pip install -e .
  fi

  # Node.js requirements
  if [ -f "package.json" ]; then
    echo ">>> Installing Node.js dependencies from package.json"
    npm install
  fi

  # Rust dependencies
  if [ -f "Cargo.toml" ]; then
    echo ">>> Installing Rust dependencies"
    cargo build
  fi

  # Go dependencies
  if [ -f "go.mod" ]; then
    echo ">>> Installing Go dependencies"
    go mod download
  fi

  # Ruby dependencies
  if [ -f "Gemfile" ]; then
    echo ">>> Installing Ruby gems from Gemfile"
    bundle install
  fi

  # Composer (PHP) dependencies
  if [ -f "composer.json" ]; then
    echo ">>> Installing PHP dependencies from composer.json"
    composer install
  fi

  echo ">>> Requirements installation complete"
}

detect_and_activate_venv() {
  if [ "$USE_VENV" = false ]; then
    echo ">>> Virtual environment disabled"
    return 0
  fi

  echo ">>> Detecting virtual environment..."

  # Check if we're already in a virtual environment (host environment)
  if [ -n "${VIRTUAL_ENV:-}" ] || [ -n "${CONDA_PREFIX:-}" ]; then
    echo ">>> Detected active virtual environment on host"

    # For venv, we need to recreate it inside the container
    if [ -n "${VIRTUAL_ENV:-}" ]; then
      VENV_NAME=$(basename "$VIRTUAL_ENV")
      echo ">>> Recreating venv '$VENV_NAME' in container"
      python -m venv "/workspace/$VENV_NAME"
      source "/workspace/$VENV_NAME/bin/activate"
      echo ">>> Activated virtual environment: /workspace/$VENV_NAME"
    fi

    # For conda, we need to recreate it inside the container
    if [ -n "${CONDA_PREFIX:-}" ]; then
      ENV_NAME=$(basename "$CONDA_PREFIX")
      echo ">>> Recreating conda environment '$ENV_NAME' in container"
      conda create -n "$ENV_NAME" --yes --clone base 2>/dev/null || conda create -n "$ENV_NAME" --yes
      eval "$(conda shell.bash hook)"
      conda activate "$ENV_NAME"
      echo ">>> Activated conda environment: $ENV_NAME"
    fi

    return 0
  fi

  # Look for common virtual environment directories
  VENV_DIRS=("venv" ".venv" "env" ".env")

  for venv_dir in "${VENV_DIRS[@]}"; do
    if [ -d "$venv_dir" ] && [ -f "$venv_dir/bin/activate" ]; then
      echo ">>> Found virtual environment: $venv_dir"
      source "/workspace/$venv_dir/bin/activate"
      echo ">>> Activated virtual environment: $venv_dir"
      return 0
    fi
  done

  # Check for conda environments
  if command -v conda &> /dev/null; then
    # Look for environment.yml or conda environment files
    if [ -f "environment.yml" ]; then
      echo ">>> Found environment.yml, creating conda environment"
      conda env create -f environment.yml --force
      eval "$(conda shell.bash hook)"
      conda activate "$(grep 'name:' environment.yml | head -1 | cut -d' ' -f2)"
      echo ">>> Activated conda environment from environment.yml"
      return 0
    fi

    # Activate default conda base environment if available
    if conda info --envs | grep -q "^base"; then
      echo ">>> Activating default conda base environment"
      eval "$(conda shell.bash hook)"
      conda activate base
      echo ">>> Activated conda base environment"
      return 0
    fi
  fi

  echo ">>> No virtual environment found"
  return 1
}

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

  cat << 'EOF'
install_requirements() {
  echo ">>> Installing repository requirements..."
  if [ -f "requirements.txt" ]; then
    echo ">>> Installing Python requirements from requirements.txt"
    pip install -r requirements.txt
  fi
  if [ -f "pyproject.toml" ]; then
    echo ">>> Installing Python package from pyproject.toml"
    pip install -e .
  fi
  if [ -f "package.json" ]; then
    echo ">>> Installing Node.js dependencies from package.json"
    npm install
  fi
  if [ -f "Cargo.toml" ]; then
    echo ">>> Installing Rust dependencies"
    cargo build
  fi
  if [ -f "go.mod" ]; then
    echo ">>> Installing Go dependencies"
    go mod download
  fi
  if [ -f "Gemfile" ]; then
    echo ">>> Installing Ruby gems from Gemfile"
    bundle install
  fi
  if [ -f "composer.json" ]; then
    echo ">>> Installing PHP dependencies from composer.json"
    composer install
  fi
  echo ">>> Requirements installation complete"
}

detect_and_activate_venv() {
  if [ "$USE_VENV" = false ]; then
    echo ">>> Virtual environment disabled"
    return 0
  fi

  echo ">>> Detecting virtual environment..."
  if [ -n "${VIRTUAL_ENV:-}" ] || [ -n "${CONDA_PREFIX:-}" ]; then
    echo ">>> Detected active virtual environment on host"
    if [ -n "${VIRTUAL_ENV:-}" ]; then
      VENV_NAME=$(basename "$VIRTUAL_ENV")
      echo ">>> Recreating venv '$VENV_NAME' in container"
      python -m venv "/workspace/$VENV_NAME"
      source "/workspace/$VENV_NAME/bin/activate"
      echo ">>> Activated virtual environment: /workspace/$VENV_NAME"
    fi
    if [ -n "${CONDA_PREFIX:-}" ]; then
      ENV_NAME=$(basename "$CONDA_PREFIX")
      echo ">>> Recreating conda environment '$ENV_NAME' in container"
      conda create -n "$ENV_NAME" --yes --clone base 2>/dev/null || conda create -n "$ENV_NAME" --yes
      eval "$(conda shell.bash hook)"
      conda activate "$ENV_NAME"
      echo ">>> Activated conda environment: $ENV_NAME"
    fi
    return 0
  fi

  VENV_DIRS=("venv" ".venv" "env" ".env")
  for venv_dir in "${VENV_DIRS[@]}"; do
    if [ -d "$venv_dir" ] && [ -f "$venv_dir/bin/activate" ]; then
      echo ">>> Found virtual environment: $venv_dir"
      source "/workspace/$venv_dir/bin/activate"
      echo ">>> Activated virtual environment: $venv_dir"
      return 0
    fi
  done

  if command -v conda &> /dev/null; then
    if [ -f "environment.yml" ]; then
      echo ">>> Found environment.yml, creating conda environment"
      conda env create -f environment.yml --force
      eval "$(conda shell.bash hook)"
      conda activate "$(grep 'name:' environment.yml | head -1 | cut -d' ' -f2)"
      echo ">>> Activated conda environment from environment.yml"
      return 0
    fi
    if conda info --envs | grep -q "^base"; then
      echo ">>> Activating default conda base environment"
      eval "$(conda shell.bash hook)"
      conda activate base
      echo ">>> Activated conda base environment"
      return 0
    fi
  fi

  echo ">>> No virtual environment found"
  return 0
}

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

# Setup docker volume and permissions
setup_docker_volume() {
  local volume_name="$1"
  local claude_home="$2"
  local user="$3"
  local image="$4"

  echo ">>> Using persistent Claude config volume: $volume_name"

  # Check if this is first run
  local volume_exists=$(docker volume ls -q -f name="^${volume_name}$")
  if [ -z "$volume_exists" ]; then
    echo ">>> First run: Creating persistent credentials volume"
    echo ">>> IMPORTANT: You'll need to complete Claude onboarding:"
    echo ">>>   1. Select your preferred theme"
    echo ">>>   2. Complete authentication (browser will open)"
    echo ">>> Your credentials will persist across all worktree sessions"

    # Create volume and set correct permissions
    docker volume create "$volume_name" > /dev/null
    docker run --rm --user root \
      -v "$volume_name:$claude_home" \
      "$image" \
      sh -c "chown -R $user:$user $claude_home && chmod 700 $claude_home"
  else
    echo ">>> Using existing credentials from persistent volume"
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
  local volume_name="$4"
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

  # Setup volume
  setup_docker_volume "$volume_name" "$claude_home" "$user" "$image"

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

  # Run the container
  docker run --rm -it \
    -v "$REPO_ROOT:/workspace" \
    -v "$volume_name:$claude_home" \
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
REPO_ROOT=$(git rev-parse --show-toplevel)
ORIGINAL_DIR=$(pwd)

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

  # Run the devcontainer with our unified function
  run_docker_container "$DEVCONTAINER_IMAGE" "node" "/home/node/.claude" "claude-devcontainer-config"

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
  run_docker_container "$CONTAINER_IMAGE" "agent" "/home/agent/.claude" "claude-sandbox-config"

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

