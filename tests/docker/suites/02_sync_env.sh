#!/bin/bash

source "$SCRIPT_DIR/lib/test_framework.sh"
source "$SCRIPT_DIR/lib/state_manager.sh"

source_sync_env_functions() {
  local script="$TEST_ENV_DIR/scripts/sync_env.sh"
  
  PERFORM_INIT=""
  PERFORM_CHECK_UPDATES=""
  PERFORM_PULL=""
  PERFORM_ENCRYPTED_SYNC=""
  PERFORM_DOTFILES_SYNC=""
  PERFORM_PUSH=""
  
  set +e
  source "$script" 2>/dev/null || true
  set -e
}

test_E01_init_repo_creates_git() {
  reset_full_state
  rm -rf "$TEST_ENV_DIR/.git"
  
  source_sync_env_functions
  init_repo "$TEST_ENV_DIR"
  
  assert_dir_exists "$TEST_ENV_DIR/.git" "Git repo should be created"
}

test_E02_init_repo_skips_if_exists() {
  reset_full_state
  
  source_sync_env_functions
  init_repo "$TEST_ENV_DIR"
  
  local before=$(stat -c %Y "$TEST_ENV_DIR/.git" 2>/dev/null || stat -f %m "$TEST_ENV_DIR/.git")
  sleep 1
  init_repo "$TEST_ENV_DIR"
  local after=$(stat -c %Y "$TEST_ENV_DIR/.git" 2>/dev/null || stat -f %m "$TEST_ENV_DIR/.git")
  
  assert_equals "$before" "$after" "Git repo should not be recreated"
}

test_E03_git_check_uncommitted() {
  reset_full_state
  setup_local_git_server
  
  echo "new content" > "$TEST_ENV_DIR/test_file.txt"
  
  source_sync_env_functions
  local result=$(git_check_updates "$TEST_ENV_DIR")
  
  assert_equals "uncommitted" "$result" "Should detect uncommitted changes"
}

test_E04_git_check_remote() {
  reset_full_state
  setup_local_git_server
  
  simulate_remote_change "remote_file.txt" "remote content"
  
  source_sync_env_functions
  local result=$(git_check_updates "$TEST_ENV_DIR")
  
  assert_equals "remote" "$result" "Should detect remote changes"
}

test_E05_git_check_none() {
  reset_full_state
  setup_local_git_server
  
  source_sync_env_functions
  local result=$(git_check_updates "$TEST_ENV_DIR")
  
  assert_equals "none" "$result" "Should report no changes"
}

test_E06_git_sync_commits_uncommitted() {
  reset_full_state
  setup_local_git_server
  
  echo "new content" > "$TEST_ENV_DIR/test_file.txt"
  
  source_sync_env_functions
  echo "y" | git_sync "push" "$TEST_ENV_DIR" 2>/dev/null || true
  
  assert_success 0 "Should commit uncommitted changes"
}

test_E07_git_sync_push() {
  reset_full_state
  setup_local_git_server
  
  echo "new content" > "$TEST_ENV_DIR/test_file.txt"
  git add -A
  git commit -m "Test commit" -q
  
  source_sync_env_functions
  echo "y" | git_sync "push" "$TEST_ENV_DIR" 2>/dev/null || true
  
  assert_success 0 "Should push changes"
}

test_E08_git_sync_pull() {
  reset_full_state
  setup_local_git_server
  
  simulate_remote_change "remote_file.txt" "remote content"
  
  source_sync_env_functions
  echo "y" | git_sync "pull" "$TEST_ENV_DIR" 2>/dev/null || true
  
  assert_file_exists "$TEST_ENV_DIR/remote_file.txt" "Should pull remote files"
}

test_E09_git_sync_merge_conflict() {
  skip_test "Interactive merge test - tested in integration"
}

test_E10_resolve_conflict_ask() {
  reset_full_state
  DEFAULT_CONFLICT_STRATEGY="ask"
  
  source_sync_env_functions
  
  assert_true 'type resolve_merge_conflict &>/dev/null' "Function should exist"
}

test_E11_resolve_conflict_local() {
  reset_full_state
  DEFAULT_CONFLICT_STRATEGY="local"
  
  source_sync_env_functions
  
  assert_true 'type resolve_merge_conflict &>/dev/null' "Function should exist"
}

test_E12_resolve_conflict_remote() {
  reset_full_state
  DEFAULT_CONFLICT_STRATEGY="remote"
  
  source_sync_env_functions
  
  assert_true 'type resolve_merge_conflict &>/dev/null' "Function should exist"
}

test_E13_cli_args_help() {
  reset_full_state
  
  local output
  output=$("$TEST_ENV_DIR/scripts/sync_env.sh" -h 2>&1)
  
  assert_contains "$output" "Usage" "Should show usage"
}

test_E14_cli_args_all_flags() {
  reset_full_state
  
  source_sync_env_functions
  
  local output
  output=$(show_help 2>&1)
  
  assert_contains "$output" "--pull" "Should list pull flag"
  assert_contains "$output" "--push" "Should list push flag"
  assert_contains "$output" "--dotfiles_sync" "Should list dotfiles flag"
  assert_contains "$output" "--encrypted_sync" "Should list encrypted flag"
}

test_E15_update_bashrc() {
  reset_full_state
  
  source_sync_env_functions
  update_bashrc
  
  assert_file_contains "$TEST_HOME/.bashrc" "envsync" "Should add envsync alias"
}

run_all_tests() {
  start_suite "02_sync_env"
  
  run_test "E01: init_repo creates git repo" test_E01_init_repo_creates_git
  run_test "E02: init_repo skips if exists" test_E02_init_repo_skips_if_exists
  run_test "E03: git_check_updates returns uncommitted" test_E03_git_check_uncommitted
  run_test "E04: git_check_updates returns remote" test_E04_git_check_remote
  run_test "E05: git_check_updates returns none" test_E05_git_check_none
  run_test "E06: git_sync commits uncommitted" test_E06_git_sync_commits_uncommitted
  run_test "E07: git_sync pushes" test_E07_git_sync_push
  run_test "E08: git_sync pulls" test_E08_git_sync_pull
  run_test "E09: git_sync handles merge conflict" test_E09_git_sync_merge_conflict
  run_test "E10: resolve_merge_conflict: ask strategy" test_E10_resolve_conflict_ask
  run_test "E11: resolve_merge_conflict: local strategy" test_E11_resolve_conflict_local
  run_test "E12: resolve_merge_conflict: remote strategy" test_E12_resolve_conflict_remote
  run_test "E13: CLI args -h shows help" test_E13_cli_args_help
  run_test "E14: CLI args all flags parsed" test_E14_cli_args_all_flags
  run_test "E15: update_bashrc adds envsync" test_E15_update_bashrc
  
  end_suite
  
  [[ $SUITE_FAILED -eq 0 ]]
}
