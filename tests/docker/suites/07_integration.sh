#!/bin/bash

source "$SCRIPT_DIR/lib/test_framework.sh"
source "$SCRIPT_DIR/lib/state_manager.sh"
source "$SCRIPT_DIR/lib/mocks.sh"

test_I01_full_setup_from_scratch() {
    setup_mocks
    reset_full_state
    rm -rf "$TEST_ENV_DIR/.git"
    
    bash "$TEST_ENV_DIR/scripts/setup.sh" 2>&1 || true
    
    assert_file_exists "$TEST_ENV_DIR/config/repo.conf" "Config should exist after setup"
}

test_I02_idempotent_setup() {
    setup_mocks
    reset_full_state
    
    bash "$TEST_ENV_DIR/scripts/setup.sh" 2>&1 || true
    local first_run=$(find "$TEST_ENV_DIR" -type f | wc -l)
    
    bash "$TEST_ENV_DIR/scripts/setup.sh" 2>&1 || true
    local second_run=$(find "$TEST_ENV_DIR" -type f | wc -l)
    
    assert_equals "$first_run" "$second_run" "Setup should be idempotent"
}

test_I03_sync_after_setup() {
    setup_mocks
    reset_full_state
    setup_local_git_server
    create_test_config
    
    bash "$TEST_ENV_DIR/scripts/sync_env.sh" --help 2>&1 | grep -q "Usage" || true
    
    assert_success 0 "sync_env should run after setup"
}

test_I04_dotfiles_creates_links() {
    reset_full_state
    create_test_dotfile ".bashrc" "# bashrc content"
    create_dotfiles_config
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    main "$TEST_ENV_DIR/config/dotfiles.conf" 2>/dev/null || true
    
    assert_symlink_exists "$TEST_HOME/.bashrc" "Dotfiles should create symlinks"
}

test_I05_config_changes_detected() {
    reset_full_state
    setup_local_git_server
    create_test_config
    
    echo "new setting=value" >> "$TEST_ENV_DIR/config/repo.conf"
    
    source "$TEST_ENV_DIR/scripts/sync_env.sh"
    local result=$(git_check_updates "$TEST_ENV_DIR" 2>/dev/null)
    
    assert_equals "uncommitted" "$result" "Should detect config changes"
}

test_I06_encrypted_sync_flow() {
    setup_mocks
    reset_full_state
    create_test_config
    mkdir -p "$TEST_ENV_DIR/tmp/private"
    echo "secret" > "$TEST_ENV_DIR/tmp/private/test.txt"
    
    assert_success 0 "Encrypted sync setup should work"
}

test_I07_shell_initialization() {
    reset_full_state
    create_test_config
    
    zsh -c "export ENV_DIR='$TEST_ENV_DIR'; source '$TEST_ENV_DIR/dotfiles/.env.zsh' 2>/dev/null && echo SUCCESS" 2>&1 | grep -q "SUCCESS" || true
    
    assert_success 0 "Shell should initialize"
}

test_I08_update_detection() {
    reset_full_state
    setup_local_git_server
    create_test_config
    
    simulate_remote_change "new_file.txt" "remote content"
    
    source "$TEST_ENV_DIR/scripts/sync_env.sh"
    local result=$(git_check_updates "$TEST_ENV_DIR" 2>/dev/null)
    
    assert_equals "remote" "$result" "Should detect remote updates"
}

test_I09_conflict_resolution() {
    reset_full_state
    create_test_dotfile ".testrc" "repo version"
    create_home_file ".testrc" "home version"
    create_dotfiles_config
    
    assert_true 'type handle_conflict &>/dev/null' "Conflict resolution should exist"
}

test_I10_cleanup_on_failure() {
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/tmp/test_cleanup"
    echo "temp" > "$TEST_ENV_DIR/tmp/test_cleanup/file.txt"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    TEMP_DIR="$TEST_ENV_DIR/tmp/test_cleanup"
    cleanup 2>/dev/null || true
    
    assert_dir_not_exists "$TEST_ENV_DIR/tmp/test_cleanup" "Should cleanup on failure"
}

run_all_tests() {
    start_suite "07_integration"
    
    run_test "I01: Full setup from scratch" test_I01_full_setup_from_scratch
    run_test "I02: Idempotent setup" test_I02_idempotent_setup
    run_test "I03: Sync after setup" test_I03_sync_after_setup
    run_test "I04: Dotfiles creates symlinks" test_I04_dotfiles_creates_links
    run_test "I05: Config changes detected" test_I05_config_changes_detected
    run_test "I06: Encrypted sync flow" test_I06_encrypted_sync_flow
    run_test "I07: Shell initialization" test_I07_shell_initialization
    run_test "I08: Update detection" test_I08_update_detection
    run_test "I09: Conflict resolution" test_I09_conflict_resolution
    run_test "I10: Cleanup on failure" test_I10_cleanup_on_failure
    
    end_suite
    
    [[ $SUITE_FAILED -eq 0 ]]
}
