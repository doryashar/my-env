#!/bin/bash

source "$SCRIPT_DIR/lib/test_framework.sh"
source "$SCRIPT_DIR/lib/state_manager.sh"
source "$SCRIPT_DIR/lib/mocks.sh"

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
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  local out rc=0
  out=$(validate_commands 2>&1) || rc=$?
  assert_success "$rc" "validate_commands passes with git and curl"
  assert_contains "$out" "Validating required commands" "the real validation ran"
}

test_S04_validate_commands_fail_no_git() {
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  local restricted out rc=0
  restricted=$(restricted_path)
  out=$(PATH="$restricted" validate_commands 2>&1) || rc=$?
  rm -rf "$restricted"

  assert_failure "$rc" "validate_commands stops when git is absent"
  assert_contains "$out" "git is required" "names the missing tool"
}

test_S05_apt_packages_skips_no_apt_get() {
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  local restricted out rc=0
  restricted=$(restricted_path)
  out=$(PATH="$restricted" install_apt_packages 2>&1) || rc=$?
  rm -rf "$restricted"

  # The "skipping" message is log_debug output, whose sanitizer needs
  # sed and therefore cannot run under a restricted PATH. The skip is
  # observable as: exit 0 and no install attempt.
  assert_success "$rc" "skips cleanly when apt-get is absent"
  assert_contains "$out" "Setting up APT packages" "reaches the APT step"
  assert_true '[[ "$out" != *"Installing missing packages"* ]]' \
    "nothing is installed"
}

test_S06_apt_packages_installs_missing() {
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  unfake_all
  FAKE_COMMANDS_LOG=$(mktemp)
  export FAKE_COMMANDS_LOG
  fake_command dpkg apt-get sudo

  # Fake dpkg reports exactly two packages missing (chosen from the
  # function's list): vim and jq.
  cat > "$FAKE_BIN_DIR/dpkg" << 'EOF'
#!/bin/bash
echo "dpkg $*" >> "${FAKE_COMMANDS_LOG:-/dev/null}"
case "${2:-}" in
  vim|jq) exit 1;;
  *) exit 0;;
esac
EOF
  chmod +x "$FAKE_BIN_DIR/dpkg"

  local rc=0
  install_apt_packages >/dev/null 2>&1 || rc=$?
  assert_success "$rc" "install_apt_packages succeeds with fakes"
  assert_equals "sudo apt-get update -qq" \
    "$(fake_calls sudo | sed -n 1p)" "first sudo call is the apt update"
  assert_equals "sudo apt-get install -y vim jq" \
    "$(fake_calls sudo | sed -n 2p)" \
    "installs exactly the two missing packages, in list order"
  assert_equals 2 "$(fake_calls sudo | wc -l)" "sudo was called exactly twice"

  unfake_all
}

test_S07_apt_packages_skips_all_present() {
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  unfake_all
  FAKE_COMMANDS_LOG=$(mktemp)
  export FAKE_COMMANDS_LOG
  fake_command dpkg apt-get sudo
  # The default fake dpkg exits 0 for every package: nothing is missing.

  local out rc=0
  out=$(ENV_DEBUG=1 install_apt_packages 2>&1) || rc=$?
  assert_success "$rc" "install_apt_packages succeeds when nothing is missing"
  assert_contains "$out" "All APT packages already installed" "reports all present"
  assert_equals "" "$(fake_calls sudo)" "sudo is never called"

  unfake_all
}

test_S08_pip_packages_skips_no_pipx() {
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  local restricted out rc=0
  restricted=$(restricted_path)
  out=$(PATH="$restricted" install_pip_packages 2>&1) || rc=$?
  rm -rf "$restricted"

  assert_success "$rc" "skips cleanly when pipx is absent"
  assert_contains "$out" "pipx not found" "message names pipx"
}

test_S09_pip_packages_installs_missing() {
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  unfake_all
  FAKE_COMMANDS_LOG=$(mktemp)
  export FAKE_COMMANDS_LOG
  fake_command pipx

  # Fake pipx reports black already installed.
  cat > "$FAKE_BIN_DIR/pipx" << 'EOF'
#!/bin/bash
echo "pipx $*" >> "${FAKE_COMMANDS_LOG:-/dev/null}"
if [[ "${1:-}" == "list" ]]; then
  echo "black"
fi
exit 0
EOF
  chmod +x "$FAKE_BIN_DIR/pipx"

  local rc=0
  install_pip_packages >/dev/null 2>&1 || rc=$?
  assert_success "$rc" "install_pip_packages succeeds with a fake pipx"
  assert_equals "pipx install python-lsp-server
pipx install flake8
pipx install pylint
pipx install neovim-remote" \
    "$(fake_calls pipx | grep '^pipx install')" \
    "installs the other four packages in the function's order"
  assert_equals 1 "$(fake_calls pipx | grep -c '^pipx list --short')" \
    "queried the installed list once"

  unfake_all
}

test_S10_docker_skips_if_present() {
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  unfake_all
  FAKE_COMMANDS_LOG=$(mktemp)
  export FAKE_COMMANDS_LOG
  fake_command docker

  mkdir -p "$TEST_ENV_DIR/scripts/install"
  cat > "$TEST_ENV_DIR/scripts/install/install_docker.sh" << EOF
#!/bin/bash
echo marker > "$TEST_ENV_DIR/tmp/docker-marker"
EOF

  local rc=0
  install_docker >/dev/null 2>&1 || rc=$?
  assert_success "$rc" "install_docker returns 0 when docker is present"
  assert_file_not_exists "$TEST_ENV_DIR/tmp/docker-marker" \
    "install script is not run when docker is present"

  unfake_all
}

test_S11_docker_calls_install_script() {
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  mkdir -p "$TEST_ENV_DIR/scripts/install"
  cat > "$TEST_ENV_DIR/scripts/install/install_docker.sh" << EOF
#!/bin/bash
echo marker > "$TEST_ENV_DIR/tmp/docker-marker"
EOF

  # A PATH without docker but with bash: the product invokes the install
  # script via `bash`, which an empty restricted PATH would hide too.
  local minimal rc=0
  minimal=$(mktemp -d)
  ln -s "$(command -v bash)" "$minimal/bash"
  PATH="$minimal" install_docker >/dev/null 2>&1 || rc=$?
  rm -rf "$minimal"

  assert_success "$rc" "install_docker succeeds without docker on PATH"
  assert_file_exists "$TEST_ENV_DIR/tmp/docker-marker" \
    "the install script was run when docker is absent"
}

test_S12_docker_compose_real_behaviour() {
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  # Without docker on PATH: skips with a warning.
  local restricted out rc=0
  restricted=$(restricted_path)
  out=$(PATH="$restricted" setup_docker_compose 2>&1) || rc=$?
  rm -rf "$restricted"
  assert_success "$rc" "setup_docker_compose returns 0 without docker"
  assert_contains "$out" "Docker not installed" "skip message names docker"

  # With docker on PATH and compose files present: starts both services.
  unfake_all
  FAKE_COMMANDS_LOG=$(mktemp)
  export FAKE_COMMANDS_LOG
  fake_command docker

  mkdir -p "$TEST_ENV_DIR/docker/rclone-mount" "$TEST_ENV_DIR/docker/zerotier"
  echo "services: {}" > "$TEST_ENV_DIR/docker/rclone-mount/docker-compose.yml"
  echo "services: {}" > "$TEST_ENV_DIR/docker/zerotier/docker-compose.yml"

  rc=0
  setup_docker_compose >/dev/null 2>&1 || rc=$?
  assert_success "$rc" "setup_docker_compose succeeds with docker present"
  assert_equals 2 "$(fake_calls docker | grep -c '^docker compose up -d$')" \
    "both compose services are started"

  unfake_all
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

test_S16_install_dotfiles_creates_link() {
  reset_full_state
  create_test_dotfile ".testrc" "test content"

  cat > "$TEST_ENV_DIR/config/dotfiles.conf" << 'EOF'
DEFAULT_LINK_TYPE="soft"
DEFAULT_CONFLICT_STRATEGY="remote"

dotfiles/.testrc => ~/.testrc
EOF

  source "$TEST_ENV_DIR/scripts/setup.sh"

  local rc=0
  install_dotfiles >/dev/null 2>&1 || rc=$?
  assert_success "$rc" "install_dotfiles succeeds"
  assert_symlink_exists "$TEST_HOME/.testrc" ".testrc should be linked"
  assert_symlink_to "$TEST_HOME/.testrc" "$TEST_ENV_DIR/dotfiles/.testrc" \
    "link points at the repo dotfile"
}

test_S17_zsh_skips_if_not_installed() {
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  local restricted out rc=0
  restricted=$(restricted_path)
  out=$(PATH="$restricted" setup_zsh 2>&1) || rc=$?
  rm -rf "$restricted"

  assert_success "$rc" "setup_zsh returns 0 when zsh is absent"
  assert_contains "$out" "ZSH not installed" "skip message names ZSH"
}

test_S18_zsh_skips_z4h_no_tty() {
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  # z4h marker present: no installer download, no terminal needed.
  touch "$TEST_HOME/.z4h.zsh"

  local out rc=0
  out=$(SHELL=/usr/bin/zsh setup_zsh 2>&1) || rc=$?
  assert_success "$rc" "setup_zsh returns 0 with zsh present and no terminal"
  assert_contains "$out" "Setting up ZSH" "runs the real setup path"
}

test_S19_encrypted_skips_no_script() {
  reset_full_state
  rm -f "$TEST_ENV_DIR/scripts/sync/sync_encrypted.sh"

  source "$TEST_ENV_DIR/scripts/setup.sh"

  local out rc=0
  out=$(sync_encrypted_files 2>&1) || rc=$?
  assert_success "$rc" "sync_encrypted_files returns 0 without the script"
  assert_contains "$out" "sync_encrypted.sh not found" "skip message names the script"
}

test_S20_create_private_repo() {
  reset_full_state

  source "$TEST_ENV_DIR/scripts/setup.sh"

  # A non-GitHub URL is rejected and named in the error.
  local out rc=0
  out=$(create_private_repo "git@bitbucket.org:owner/repo.git" </dev/null 2>&1) || rc=$?
  assert_failure "$rc" "rejects a non-GitHub URL"
  assert_contains "$out" "git@bitbucket.org:owner/repo.git" "error names the URL"

  # A GitHub URL with the mock gh asks gh to create the private repo.
  setup_mocks
  MOCK_GH_CALLS_LOG=$(mktemp)
  export MOCK_GH_CALLS_LOG

  rc=0
  out=$(create_private_repo "git@github.com:owner/env-repo.git" </dev/null 2>&1) || rc=$?
  assert_success "$rc" "creates the repo via gh"
  assert_contains "$out" "Repository created successfully" "success is reported"
  assert_contains "$(cat "$MOCK_GH_CALLS_LOG")" \
    "gh repo create owner/env-repo --private" "gh was asked to create it private"

  rm -f "$MOCK_GH_CALLS_LOG"
  unset MOCK_GH_CALLS_LOG
}

run_all_tests() {
  start_suite "01_setup"

  run_test "S01: Config generation creates repo.conf" test_S01_config_generation
  run_test "S02: Config not overwritten if exists" test_S02_config_not_overwritten
  run_test "S03: validate_commands passes with git+curl" test_S03_validate_commands_pass
  run_test "S04: validate_commands fails without required command" test_S04_validate_commands_fail_no_git
  run_test "S05: apt_packages skips non-Debian" test_S05_apt_packages_skips_no_apt_get
  run_test "S06: apt_packages installs missing" test_S06_apt_packages_installs_missing
  run_test "S07: apt_packages skips if all present" test_S07_apt_packages_skips_all_present
  run_test "S08: pip_packages skips if no pipx" test_S08_pip_packages_skips_no_pipx
  run_test "S09: pip_packages installs missing" test_S09_pip_packages_installs_missing
  run_test "S10: docker skips if present" test_S10_docker_skips_if_present
  run_test "S11: docker calls install script" test_S11_docker_calls_install_script
  run_test "S12: docker_compose real behaviour" test_S12_docker_compose_real_behaviour
  run_test "S13: binaries makes AppImage executable" test_S13_binaries_makes_appimage_executable
  run_test "S14: binaries extracts tar.gz" test_S14_binaries_extracts_targz
  run_test "S15: cron creates default crontab" test_S15_cron_creates_default
  run_test "S16: install_dotfiles creates the link" test_S16_install_dotfiles_creates_link
  run_test "S17: zsh skips if not installed" test_S17_zsh_skips_if_not_installed
  run_test "S18: zsh skips z4h without TTY" test_S18_zsh_skips_z4h_no_tty
  run_test "S19: encrypted skips if no script" test_S19_encrypted_skips_no_script
  run_test "S20: create_private_repo real behaviour" test_S20_create_private_repo

  end_suite

  [[ $SUITE_FAILED -eq 0 ]]
}
