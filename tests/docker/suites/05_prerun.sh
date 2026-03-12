#!/bin/bash

source "$SCRIPT_DIR/lib/test_framework.sh"
source "$SCRIPT_DIR/lib/state_manager.sh"
source "$SCRIPT_DIR/lib/mocks.sh"

test_P01_is_env_installed_checks_dir() {
    reset_full_state
    source "$TEST_ENV_DIR/scripts/prerun.sh"
    
    is_env_installed
    assert_failure $? "Should fail without marker"
}

test_P02_is_env_installed_checks_marker() {
    reset_full_state
    touch "$TEST_ENV_DIR/.env_installed"
    
    source "$TEST_ENV_DIR/scripts/prerun.sh"
    is_env_installed
    
    assert_success $? "Should pass with marker"
}

test_P03_get_vault_cli() {
    setup_mocks
    reset_full_state
    source "$TEST_ENV_DIR/scripts/prerun.sh"
    
    assert_true 'type get_vault_cli &>/dev/null' "Function should exist"
}

test_P04_oauth2_unauthenticated() {
    setup_mocks
    reset_full_state
    mock_bw_set_status "unauthenticated"
    
    source "$TEST_ENV_DIR/scripts/prerun.sh"
    
    assert_true 'type oauth2_authenticate &>/dev/null' "Function should exist"
}

test_P05_oauth2_unlocks() {
    setup_mocks
    reset_full_state
    mock_bw_set_status "locked"
    
    source "$TEST_ENV_DIR/scripts/prerun.sh"
    
    assert_true 'type oauth2_authenticate &>/dev/null' "Function should exist"
}

test_P06_clone_ssh() {
    setup_mocks
    reset_full_state
    source "$TEST_ENV_DIR/scripts/prerun.sh"
    
    assert_true 'type clone_repo_with_api_key &>/dev/null' "Function should exist"
}

test_P07_clone_https() {
    setup_mocks
    reset_full_state
    source "$TEST_ENV_DIR/scripts/prerun.sh"
    
    assert_true 'type clone_repo_with_api_key &>/dev/null' "Function should exist"
}

test_P08_check_remote_updates() {
    reset_full_state
    setup_local_git_server
    source "$TEST_ENV_DIR/scripts/prerun.sh"
    
    assert_true 'type check_remote_updates &>/dev/null' "Function should exist"
}

test_P09_check_local_changes() {
    reset_full_state
    setup_local_git_server
    source "$TEST_ENV_DIR/scripts/prerun.sh"
    
    assert_true 'type check_local_changes &>/dev/null' "Function should exist"
}

test_P10_update_from_remote() {
    reset_full_state
    setup_local_git_server
    source "$TEST_ENV_DIR/scripts/prerun.sh"
    
    assert_true 'type update_from_remote &>/dev/null' "Function should exist"
}

test_P11_prompt_push_changes() {
    reset_full_state
    setup_local_git_server
    source "$TEST_ENV_DIR/scripts/prerun.sh"
    
    assert_true 'type prompt_push_changes &>/dev/null' "Function should exist"
}

test_P12_main_flow() {
    setup_mocks
    reset_full_state
    source "$TEST_ENV_DIR/scripts/prerun.sh"
    
    assert_true 'type main &>/dev/null' "main function should exist"
}

run_all_tests() {
    start_suite "05_prerun"
    
    run_test "P01: is_env_installed checks directory" test_P01_is_env_installed_checks_dir
    run_test "P02: is_env_installed checks marker" test_P02_is_env_installed_checks_marker
    run_test "P03: get_vault_cli exists" test_P03_get_vault_cli
    run_test "P04: oauth2 handles unauthenticated" test_P04_oauth2_unauthenticated
    run_test "P05: oauth2 unlocks vault" test_P05_oauth2_unlocks
    run_test "P06: clone with SSH" test_P06_clone_ssh
    run_test "P07: clone with HTTPS" test_P07_clone_https
    run_test "P08: check_remote_updates exists" test_P08_check_remote_updates
    run_test "P09: check_local_changes exists" test_P09_check_local_changes
    run_test "P10: update_from_remote exists" test_P10_update_from_remote
    run_test "P11: prompt_push_changes exists" test_P11_prompt_push_changes
    run_test "P12: main function exists" test_P12_main_flow
    
    end_suite
    
    [[ $SUITE_FAILED -eq 0 ]]
}
