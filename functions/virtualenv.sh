#!/usr/bin/env bash
# Virtual Environment Management Functions
# Sourced by new_claude.sh and used in container commands

# Install project dependencies based on detected project files
#
# Detects and installs dependencies for:
#   - Python (requirements.txt, pyproject.toml)
#   - Node.js (package.json)
#   - Rust (Cargo.toml)
#   - Go (go.mod)
#   - Ruby (Gemfile)
#   - PHP (composer.json)
#
# Returns:
#   0 - Success
#
# Side Effects:
#   - Installs packages globally or in current environment
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

# Detect and activate a Python virtual environment
#
# Supports:
#   - venv (.venv, venv, env, .env)
#   - conda environments (environment.yml or base)
#   - Recreates host virtual environments in container
#
# Uses environment variables:
#   USE_VENV - Set to "false" to disable detection
#   VIRTUAL_ENV - Host venv path (if active)
#   CONDA_PREFIX - Host conda environment path (if active)
#
# Returns:
#   0 - Success or no venv found
#   1 - No venv found (legacy behavior)
#
# Side Effects:
#   - Activates virtual environment in shell
#   - May create new venv in container
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
  return 0
}
