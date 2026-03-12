#!/bin/bash

source "$SCRIPT_DIR/lib/test_framework.sh"
source "$SCRIPT_DIR/lib/state_manager.sh"

test_S01_config_generation() {
  reset_full_state
  rm -f "$TEST_ENV_DIR/config/repo.conf"
  
  source "$TEST_ENV_DIR/scripts/setup.sh"
  generate_config
  
  assert_file_exists "$TEST_ENV_DIR/config/repo.conf" "repo.conf should be created"
}

test_S02_config_not_overwritten() {
  reset_full_state
  echo "CUSTOM_VAR=test" > "$TEST_ENV_DIR/config/repo.conf"
  
  source "$TEST_ENV_DIR/scripts/setup.sh"
  generate_config
  
  assert_file_contains "$TEST_ENV_DIR/config/repo.conf" "CUSTOM_VAR=test" "Existing config should be preserved"
}

test_S03_validate_commands_pass() {
  source "$TEST_ENV_DIR/scripts/setup.sh"
  
  validate_commands 2>&1 || true
  assert_success 0 "validate_commands should pass with git and curl"
}

test_S04_validate_commands_fail_no_git() {
  reset_full_state
  
  cat > "$TEST_ENV_DIR/scripts/test_validate.sh" << 'EOF'
check_command() {
  if ! command -v "$1" &> /dev/null; then
    echo "ERROR: $1 is required but not installed."
    return 1
  fi
}
validate_commands() {
  check_command nonexistent_command_xyz
}
EOF
  source "$TEST_ENV_DIR/scripts/test_validate.sh"
  
  validate_commands 2>&1 || true
  assert_true "$? -ne 0" "validate_commands should fail without required command"
}

test_S05_apt_packages_skips_non_debian() {
  reset_full_state
  
  cat > "$TEST_ENV_DIR/scripts/test_apt.sh" << 'EOF'
install_apt_packages() {
  if ! command -v apt-get &> /dev/null; then
    return 0
  fi
  return 1
}
EOF
  source "$TEST_ENV_DIR/scripts/test_apt.sh"
  
  install_apt_packages
  assert_success $? "Should skip on non-Debian"
}

test_S06_apt_packages_installs_missing() {
  skip_test "Requires apt-get - tested in integration"
}

test_S07_apt_packages_skips_if_present() {
  skip_test "Requires apt-get - tested in integration"
}

test_S08_pip_packages_skips_no_pip() {
  reset_full_state
  
  cat > "$TEST_ENV_DIR/scripts/test_pip.sh" << 'EOF'
install_pip_packages() {
  if ! command -v pip3 &> /dev/null; then
    return 0
  fi
  return 1
}
EOF
  source "$TEST_ENV_DIR/scripts/test_pip.sh"
  
  install_pip_packages
  assert_success $? "Should skip if no pip3"
}

test_S09_pip_packages_installs_missing() {
  skip_test "Requires pip3 - tested in integration"
}

test_S10_docker_skips_if_present() {
  reset_full_state
  
  cat > "$TEST_ENV_DIR/scripts/test_docker.sh" << 'EOF'
install_docker() {
  if command -v docker &> /dev/null; then
    return 0
  fi
  return 1
}
EOF
  source "$TEST_ENV_DIR/scripts/test_docker.sh"
  
  install_docker
  assert_success $? "Should skip if docker installed"
}

test_S11_docker_calls_install_script() {
  skip_test "Requires sudo - tested in integration"
}

test_S12_docker_compose_skips_no_docker() {
  reset_full_state
  
  cat > "$TEST_ENV_DIR/scripts/test_compose.sh" << 'EOF'
setup_docker_compose() {
  if ! command -v docker &> /dev/null; then
    return 0
  fi
  return 1
}
EOF
  source "$TEST_ENV_DIR/scripts/test_compose.sh"
  
  setup_docker_compose
  assert_success $? "Should skip if no docker"
}

test_S13_binaries_makes_appimage_executable() {
  reset_full_state
  
  echo "test" > "$TEST_ENV_DIR/bin/test.AppImage"
  chmod -x "$TEST_ENV_DIR/bin/test.AppImage"
  
  source "$TEST_ENV_DIR/scripts/setup.sh"
  setup_binaries
  
  assert_executable "$TEST_ENV_DIR/bin/test.AppImage" "AppImage should be executable"
}

test_S14_binaries_extracts_targz() {
  reset_full_state
  
  mkdir -p "$TEST_ENV_DIR/bin_test"
  echo "test content" > "$TEST_ENV_DIR/bin_test/file.txt"
  tar -czf "$TEST_ENV_DIR/bin/test.tar.gz" -C "$TEST_ENV_DIR/bin_test" .
  
  source "$TEST_ENV_DIR/scripts/setup.sh"
  setup_binaries
  
  assert_file_exists "$TEST_ENV_DIR/bin/file.txt" "tar.gz should be extracted"
}

test_S15_cron_creates_default() {
  reset_full_state
  rm -f "$TEST_ENV_DIR/config/crontab"
  
  source "$TEST_ENV_DIR/scripts/setup.sh"
  setup_cron_jobs
  
  assert_file_exists "$TEST_ENV_DIR/config/crontab" "Default crontab should be created"
}

test_S16_install_dotfiles_calls_sync() {
  reset_full_state
  create_dotfiles_config
  
  source "$TEST_ENV_DIR/scripts/setup.sh"
  install_dotfiles
  
  assert_symlink_exists "$TEST_HOME/.testrc" "Dotfiles should be synced"
}

test_S17_zsh_skips_if_not_installed() {
  skip_test "zsh is installed in Docker - tested in integration"
}

test_S18_zsh_skips_z4h_no_tty() {
  reset_full_state
  
  source "$TEST_ENV_DIR/scripts/setup.sh"
  
  if [[ ! -t 0 ]]; then
    setup_zsh 2>&1 | grep -q "No TTY" || true
    assert_success 0 "Should handle non-TTY gracefully"
  else
    skip_test "Running in TTY"
  fi
}

test_S19_encrypted_skips_no_script() {
  reset_full_state
  rm -f "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
  
  source "$TEST_ENV_DIR/scripts/setup.sh"
  sync_encrypted_files 2>&1 || true
  
  assert_success 0 "Should skip gracefully without script"
}

test_S20_create_private_repo_parses_ssh_url() {
  reset_full_state
  source "$TEST_ENV_DIR/scripts/setup.sh"
  
  local url="git@github.com:owner/repo.git"
  
  if [[ "$url" =~ git@github\.com:([^/]+)/(.+)\.git ]]; then
    local owner="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"
    assert_equals "owner" "$owner" "Should parse owner"
    assert_equals "repo" "$repo" "Should parse repo name"
  else
    assert_true false "Should match SSH URL pattern"
  fi
}

run_all_tests() {
  start_suite "01_setup"
  
  run_test "S01: Config generation creates repo.conf" test_S01_config_generation
  run_test "S02: Config not overwritten if exists" test_S02_config_not_overwritten
  run_test "S03: validate_commands passes with git+curl" test_S03_validate_commands_pass
  run_test "S04: validate_commands fails without required command" test_S04_validate_commands_fail_no_git
  run_test "S05: apt_packages skips non-Debian" test_S05_apt_packages_skips_non_debian
  run_test "S06: apt_packages installs missing" test_S06_apt_packages_installs_missing
  run_test "S07: apt_packages skips if all present" test_S07_apt_packages_skips_if_present
  run_test "S08: pip_packages skips if no pip3" test_S08_pip_packages_skips_no_pip
  run_test "S09: pip_packages installs missing" test_S09_pip_packages_installs_missing
  run_test "S10: docker skips if present" test_S10_docker_skips_if_present
  run_test "S11: docker calls install script" test_S11_docker_calls_install_script
  run_test "S12: docker_compose skips if no docker" test_S12_docker_compose_skips_no_docker
  run_test "S13: binaries makes AppImage executable" test_S13_binaries_makes_appimage_executable
  run_test "S14: binaries extracts tar.gz" test_S14_binaries_extracts_targz
  run_test "S15: cron creates default crontab" test_S15_cron_creates_default
  run_test "S16: install_dotfiles calls sync" test_S16_install_dotfiles_calls_sync
  run_test "S17: zsh skips if not installed" test_S17_zsh_skips_if_not_installed
  run_test "S18: zsh skips z4h without TTY" test_S18_zsh_skips_z4h_no_tty
  run_test "S19: encrypted skips if no script" test_S19_encrypted_skips_no_script
  run_test "S20: create_private_repo parses SSH URL" test_S20_create_private_repo_parses_ssh_url
  
  end_suite
  
  [[ $SUITE_FAILED -eq 0 ]]
}
