#!/bin/bash

ORIGINAL_ENV_DIR="${ORIGINAL_ENV_DIR:-/home/testuser/env}"
ORIGINAL_HOME="${ORIGINAL_HOME:-/home/testuser}"
TEST_ROOT=""
TEST_ENV_DIR=""
TEST_HOME=""

TEST_GIT_SERVER=""

init_state_manager() {
  TEST_ROOT=$(mktemp -d -t env-test-root-XXXXXX)
  TEST_ENV_DIR="$TEST_ROOT/env"
  TEST_HOME="$TEST_ROOT/home"
  
  mkdir -p "$TEST_ENV_DIR"/{scripts,config,functions,dotfiles,bin,tmp,private}
  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_ROOT"/{git-server,cache}
  
  ORIGINAL_ENV_DIR="${ORIGINAL_ENV_DIR:-$ENV_DIR}"
  ORIGINAL_HOME="${ORIGINAL_HOME:-$HOME}"
}

reset_full_state() {
  rm -rf "$TEST_ROOT"
  init_state_manager
  
  copy_env_files
  
  setup_test_git_config
}

reset_home_state() {
  rm -rf "$TEST_HOME"
  mkdir -p "$TEST_HOME"
}

reset_env_state() {
  rm -rf "$TEST_ENV_DIR"
  mkdir -p "$TEST_ENV_DIR"/{scripts,config,functions,dotfiles,bin,tmp,private}
  copy_env_files
  setup_test_git_config
}

copy_env_files() {
  cp -r "$ORIGINAL_ENV_DIR"/scripts/* "$TEST_ENV_DIR/scripts/" 2>/dev/null || true
  cp -r "$ORIGINAL_ENV_DIR"/functions/* "$TEST_ENV_DIR/functions/" 2>/dev/null || true
  cp -r "$ORIGINAL_ENV_DIR"/dotfiles/* "$TEST_ENV_DIR/dotfiles/" 2>/dev/null || true
  cp -r "$ORIGINAL_ENV_DIR"/config/* "$TEST_ENV_DIR/config/" 2>/dev/null || true
  cp "$ORIGINAL_ENV_DIR"/aliases "$TEST_ENV_DIR/aliases" 2>/dev/null || true
  cp "$ORIGINAL_ENV_DIR"/env_vars "$TEST_ENV_DIR/env_vars" 2>/dev/null || true
  
  chmod +x "$TEST_ENV_DIR"/scripts/*.sh 2>/dev/null || true
  
  mkdir -p "$TEST_ENV_DIR/tests/docker/lib" "$TEST_ENV_DIR/tests/docker/suites"
  cp -r "$ORIGINAL_ENV_DIR"/tests/docker/lib/* "$TEST_ENV_DIR/tests/docker/lib/" 2>/dev/null || true
  cp -r "$ORIGINAL_ENV_DIR"/tests/docker/suites/* "$TEST_ENV_DIR/tests/docker/suites/" 2>/dev/null || true
  cp -r "$ORIGINAL_ENV_DIR"/tests/docker/run_tests.sh "$TEST_ENV_DIR/tests/docker/" 2>/dev/null || true
  chmod +x "$TEST_ENV_DIR"/tests/docker/*.sh 2>/dev/null || true
  chmod +x "$TEST_ENV_DIR"/tests/docker/suites/*.sh 2>/dev/null || true
}

setup_test_git_config() {
  TEST_ENV_DIR_BACKUP="$ENV_DIR"
  TEST_HOME_BACKUP="$HOME"
  
  export ENV_DIR="$TEST_ENV_DIR"
  export HOME="$TEST_HOME"
  
  cd "$TEST_ENV_DIR"
  
  if [[ ! -d ".git" ]]; then
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test User"
  fi
}

setup_local_git_server() {
  TEST_GIT_SERVER="$TEST_ROOT/git-server"
  
  mkdir -p "$TEST_GIT_SERVER"/env.git
  cd "$TEST_GIT_SERVER"/env.git
  git init --bare -q
  
  mkdir -p "$TEST_GIT_SERVER"/encrypted.git
  cd "$TEST_GIT_SERVER"/encrypted.git
  git init --bare -q
  
  cd "$TEST_ENV_DIR"
  git remote remove origin 2>/dev/null || true
  git remote add origin "$TEST_GIT_SERVER/env.git"
  
  git add -A
  git commit -m "Initial commit" -q 2>/dev/null || true
  git push -u origin master -q 2>/dev/null || true
}

create_test_file() {
  local path="$1"
  local content="${2:-test content}"
  
  local full_path
  if [[ "$path" == /* ]]; then
    full_path="$path"
  else
    full_path="$TEST_ENV_DIR/$path"
  fi
  
  mkdir -p "$(dirname "$full_path")"
  echo "$content" > "$full_path"
  echo "$full_path"
}

create_test_dotfile() {
  local name="$1"
  local content="${2:-# test dotfile}"
  
  local dotfile_path="$TEST_ENV_DIR/dotfiles/$name"
  mkdir -p "$(dirname "$dotfile_path")"
  echo "$content" > "$dotfile_path"
  echo "$dotfile_path"
}

create_home_file() {
  local name="$1"
  local content="${2:-# test file}"
  
  local home_path="$TEST_HOME/$name"
  mkdir -p "$(dirname "$home_path")"
  echo "$content" > "$home_path"
  echo "$home_path"
}

create_test_config() {
  cat > "$TEST_ENV_DIR/config/repo.conf" << EOF
REMOTE_URL="file://$TEST_GIT_SERVER/env.git"
ENV_DIR="$TEST_ENV_DIR"
BW_EMAIL="test@test.com"
PRIVATE_URL="file://$TEST_GIT_SERVER/encrypted.git"
SHOW_DUFF=off
SHOW_NEOFETCH=off
EOF
}

create_dotfiles_config() {
  cat > "$TEST_ENV_DIR/config/dotfiles.conf" << EOF
DEFAULT_LINK_TYPE="soft"
DEFAULT_CONFLICT_STRATEGY="remote"

dotfiles/.bashrc => ~/.bashrc
dotfiles/.zshrc => ~/.zshrc
dotfiles/.testrc => ~/.testrc
config/* => ~/.config/*
EOF
}

create_encrypted_test_file() {
  local name="$1"
  local content="${2:-secret content}"
  
  local encrypted_dir="$TEST_ENV_DIR/tmp/private"
  mkdir -p "$encrypted_dir"
  
  echo "$content" > "$encrypted_dir/$name"
  
  local encrypted_repo="$TEST_ENV_DIR/tmp/private_encrypted"
  mkdir -p "$encrypted_repo"
  echo "age-encryption.org/v1" > "$encrypted_repo/${name}.age"
  echo "$content" >> "$encrypted_repo/${name}.age"
  
  echo "$encrypted_dir/$name"
}

simulate_remote_change() {
  local file="$1"
  local content="$2"
  
  local clone_dir=$(mktemp -d)
  git clone "$TEST_GIT_SERVER/env.git" "$clone_dir" -q
  
  echo "$content" > "$clone_dir/$file"
  cd "$clone_dir"
  git add -A
  git commit -m "Remote change" -q
  git push -q
  
  rm -rf "$clone_dir"
  cd "$TEST_ENV_DIR"
}

simulate_local_change() {
  local file="$1"
  local content="$2"
  
  echo "$content" > "$TEST_ENV_DIR/$file"
}

cleanup_state() {
  local original_dir="${ORIGINAL_ENV_DIR:-$ENV_DIR}"
  
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
    rm -rf "$TEST_ROOT"
  fi
  
  cd "$original_dir" 2>/dev/null || cd /home/testuser/env
  
  if [[ -n "$ORIGINAL_ENV_DIR" ]]; then
    export ENV_DIR="$ORIGINAL_ENV_DIR"
  fi
  if [[ -n "$ORIGINAL_HOME" ]]; then
    export HOME="$ORIGINAL_HOME"
  fi
}

with_clean_env() {
  local func="$1"
  
  reset_full_state
  $func
  local result=$?
  cleanup_state
  
  return $result
}

get_test_env_dir() {
  echo "$TEST_ENV_DIR"
}

get_test_home() {
  echo "$TEST_HOME"
}

get_test_git_server() {
  echo "$TEST_GIT_SERVER"
}
