#!/bin/bash

source "$SCRIPT_DIR/lib/test_framework.sh"
source "$SCRIPT_DIR/lib/state_manager.sh"
source "$SCRIPT_DIR/lib/mocks.sh"

# Run .env.zsh in a real zsh with the test HOME/ENV_DIR.
# $1 = zsh code executed before sourcing (e.g. variable assignments)
# $2 = zsh code executed after sourcing (e.g. a print to check)
# The suite asserts the real exit codes and real output.
zsh_source_env() {
  local pre="${1-}"
  local post="${2-}"
  env HOME="$TEST_HOME" ENV_DIR="$TEST_ENV_DIR" zsh -c \
    "$pre
source \"\$ENV_DIR/dotfiles/.env.zsh\"
$post"
}

test_Z01_env_zsh_loads() {
  reset_full_state

  local rc=0
  zsh -n "$TEST_ENV_DIR/dotfiles/.env.zsh" || rc=$?

  assert_success "$rc" "zsh -n: .env.zsh has valid syntax"
}

test_Z02_sources_repo_conf() {
  reset_full_state
  echo 'REMOTE_URL="git@github.com:fork/env.git"' > "$TEST_ENV_DIR/config/repo.conf"

  local out rc=0
  out=$(zsh_source_env "" 'print -r -- "$REMOTE_URL"') || rc=$?
  assert_success "$rc" "sourcing .env.zsh exits 0"
  assert_equals "git@github.com:fork/env.git" "$out" \
    "a value set by config/repo.conf is loaded"
}

test_Z03_sources_env_vars() {
  reset_full_state

  local out rc=0
  out=$(zsh_source_env "" 'print -r -- "$EDITOR"') || rc=$?
  assert_success "$rc" "sourcing .env.zsh exits 0"
  assert_equals "nvim" "$out" "a value from env_vars is loaded"
}

test_Z04_sources_private_secrets() {
  reset_full_state
  mkdir -p "$TEST_ENV_DIR/var/private"
  echo 'export ZTEST_SECRET="ztest-secret-value"' > "$TEST_ENV_DIR/var/private/secrets"

  local out rc=0
  out=$(zsh_source_env "" 'print -r -- "$ZTEST_SECRET"') || rc=$?
  assert_success "$rc" "sourcing .env.zsh exits 0"
  assert_equals "ztest-secret-value" "$out" \
    "a secret from the private file is exported"
}

test_Z05_sources_functions() {
  reset_full_state

  local out rc=0
  out=$(zsh_source_env "" 'type file_age_days >/dev/null && echo defined') || rc=$?
  assert_success "$rc" "sourcing .env.zsh exits 0"
  assert_equals "defined" "$out" "a function the file defines is available"
}

test_Z06_sources_env_funcs() {
  reset_full_state

  local out rc=0
  out=$(zsh_source_env "" 'type notify >/dev/null && echo defined') || rc=$?
  assert_success "$rc" "sourcing .env.zsh exits 0"
  assert_equals "defined" "$out" "notify from env_funcs is defined"
}

test_Z07_sources_aliases() {
  reset_full_state

  local out rc=0
  out=$(zsh_source_env "" 'alias ll') || rc=$?
  assert_success "$rc" "sourcing .env.zsh exits 0"
  assert_contains "$out" "ls --color -altr" "the alias file was sourced"
}

test_Z08_duff_on_loads() {
  reset_full_state

  local rc=0
  zsh_source_env "SHOW_DUFF=on" "" || rc=$?
  assert_success "$rc" "sourcing with SHOW_DUFF=on exits 0"
}

test_Z09_duff_off_loads() {
  reset_full_state

  local rc=0
  zsh_source_env "SHOW_DUFF=off" "" || rc=$?
  assert_success "$rc" "sourcing with SHOW_DUFF=off exits 0"
}

test_Z10_neofetch_on_loads() {
  reset_full_state

  local rc=0
  zsh_source_env "SHOW_NEOFETCH=on" "" || rc=$?
  assert_success "$rc" "sourcing with SHOW_NEOFETCH=on exits 0"
}

test_Z11_neofetch_off_loads() {
  reset_full_state

  local rc=0
  zsh_source_env "SHOW_NEOFETCH=off" "" || rc=$?
  assert_success "$rc" "sourcing with SHOW_NEOFETCH=off exits 0"
}

test_Z12_common_funcs_debug_sanitizes() {
  reset_full_state

  # debug() is gone; log_debug replaces secrets in the output.
  local rc=0
  zsh_source_env "" "type debug" >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "debug() no longer exists"

  local out rc2=0
  out=$(env HOME="$TEST_HOME" ENV_DIR="$TEST_ENV_DIR" ENV_DEBUG=1 \
    zsh -c 'source "$ENV_DIR/dotfiles/.env.zsh"; log_debug "AGE_SECRET=topsecret-value"' \
    2>&1) || rc2=$?
  assert_success "$rc2" "log_debug runs with ENV_DEBUG=1"
  assert_contains "$out" "AGE_SECRET=***HIDDEN***" "the secret is replaced in the output"
  assert_false '[[ "$out" == *topsecret-value* ]]' "the raw secret is not printed"
}

test_Z13_common_funcs_warning() {
  reset_full_state

  local out rc=0
  out=$(zsh_source_env "" 'warning "warn-marker-xyz"' 2>&1) || rc=$?
  assert_success "$rc" "warning returns 0"
  assert_contains "$out" "warn-marker-xyz" "warning prints its message"
}

test_Z14_common_funcs_error() {
  reset_full_state

  local out rc=0
  out=$(zsh_source_env "" 'error "err-marker-xyz"' 2>&1) || rc=$?
  assert_equals 1 "$rc" "error exits 1 in a subshell"
  assert_contains "$out" "err-marker-xyz" "error prints to stderr"
}

test_Z15_git_funcs_has_remote() {
  reset_full_state
  create_test_config
  setup_local_git_server

  local rc=0
  zsh_source_env "" 'git_has_remote_updates "$ENV_DIR"' || rc=$?
  assert_equals 1 "$rc" "fresh push: no remote updates"

  simulate_remote_change "remote_file.txt" "remote content"
  rc=0
  zsh_source_env "" 'git_has_remote_updates "$ENV_DIR"' || rc=$?
  assert_equals 0 "$rc" "remote commit is detected"
}

test_Z16_git_funcs_has_local() {
  reset_full_state
  create_test_config
  setup_local_git_server

  local rc=0
  zsh_source_env "" 'git_has_local_changes "$ENV_DIR"' || rc=$?
  assert_equals 1 "$rc" "clean tree: no local changes"

  echo "new setting=value" >> "$TEST_ENV_DIR/config/repo.conf"
  rc=0
  zsh_source_env "" 'git_has_local_changes "$ENV_DIR"' || rc=$?
  assert_equals 0 "$rc" "modified tracked file is detected"
}

test_Z17_git_funcs_safe_pull() {
  reset_full_state
  create_test_config
  setup_local_git_server

  simulate_remote_change "pulled_file.txt" "pulled content"

  local rc=0
  zsh_source_env "" 'git_safe_pull "$ENV_DIR"' || rc=$?
  assert_success "$rc" "git_safe_pull succeeds on a ff-only update"
  assert_file_contains "$TEST_ENV_DIR/pulled_file.txt" "pulled content" \
    "the pulled file is present after the pull"
}

run_all_tests() {
  start_suite "06_env_zsh"

  run_test "Z01: .env.zsh has valid syntax" test_Z01_env_zsh_loads
  run_test "Z02: sources repo.conf" test_Z02_sources_repo_conf
  run_test "Z03: sources env_vars" test_Z03_sources_env_vars
  run_test "Z04: sources private secrets" test_Z04_sources_private_secrets
  run_test "Z05: sources functions" test_Z05_sources_functions
  run_test "Z06: sources env_funcs" test_Z06_sources_env_funcs
  run_test "Z07: sources aliases" test_Z07_sources_aliases
  run_test "Z08: SHOW_DUFF=on loads" test_Z08_duff_on_loads
  run_test "Z09: SHOW_DUFF=off loads" test_Z09_duff_off_loads
  run_test "Z10: SHOW_NEOFETCH=on loads" test_Z10_neofetch_on_loads
  run_test "Z11: SHOW_NEOFETCH=off loads" test_Z11_neofetch_off_loads
  run_test "Z12: log_debug sanitizes secrets" test_Z12_common_funcs_debug_sanitizes
  run_test "Z13: warning prints message" test_Z13_common_funcs_warning
  run_test "Z14: error exits 1" test_Z14_common_funcs_error
  run_test "Z15: git_has_remote_updates" test_Z15_git_funcs_has_remote
  run_test "Z16: git_has_local_changes" test_Z16_git_funcs_has_local
  run_test "Z17: git_safe_pull" test_Z17_git_funcs_safe_pull

  end_suite

  [[ $SUITE_FAILED -eq 0 ]]
}
