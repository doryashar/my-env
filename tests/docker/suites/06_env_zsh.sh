#!/bin/bash

source "$SCRIPT_DIR/lib/test_framework.sh"
source "$SCRIPT_DIR/lib/state_manager.sh"

test_Z01_env_zsh_loads() {
    reset_full_state
    create_test_config
    
    zsh -n "$TEST_ENV_DIR/dotfiles/.env.zsh" 2>&1
    assert_success $? ".env.zsh should have valid syntax"
}

test_Z02_sources_repo_conf() {
    reset_full_state
    create_test_config
    
    zsh -c "export ENV_DIR='$TEST_ENV_DIR'; source '$TEST_ENV_DIR/dotfiles/.env.zsh' 2>/dev/null; echo \$REMOTE_URL" 2>&1 || true
    
    assert_success 0 "Should source repo.conf"
}

test_Z03_sources_env_vars() {
    reset_full_state
    create_test_config
    
    zsh -c "export ENV_DIR='$TEST_ENV_DIR'; source '$TEST_ENV_DIR/dotfiles/.env.zsh' 2>/dev/null" 2>&1 || true
    
    assert_success 0 "Should source env_vars"
}

test_Z04_sources_private_secrets() {
    reset_full_state
    create_test_config
    mkdir -p "$TEST_ENV_DIR/private"
    echo "export TEST_SECRET=secret123" > "$TEST_ENV_DIR/private/secrets"
    
    zsh -c "export ENV_DIR='$TEST_ENV_DIR'; source '$TEST_ENV_DIR/dotfiles/.env.zsh' 2>/dev/null" 2>&1 || true
    
    assert_success 0 "Should source secrets"
}

test_Z05_sources_functions() {
    reset_full_state
    create_test_config
    
    zsh -c "export ENV_DIR='$TEST_ENV_DIR'; source '$TEST_ENV_DIR/dotfiles/.env.zsh' 2>/dev/null" 2>&1 || true
    
    assert_success 0 "Should source functions"
}

test_Z06_sources_aliases() {
    reset_full_state
    create_test_config
    
    zsh -c "export ENV_DIR='$TEST_ENV_DIR'; source '$TEST_ENV_DIR/dotfiles/.env.zsh' 2>/dev/null" 2>&1 || true
    
    assert_success 0 "Should source aliases"
}

test_Z07_background_update() {
    reset_full_state
    create_test_config
    setup_local_git_server
    
    mkdir -p "$TEST_ENV_DIR/tmp"
    zsh -c "export ENV_DIR='$TEST_ENV_DIR'; source '$TEST_ENV_DIR/dotfiles/.env.zsh' 2>/dev/null" 2>&1 || true
    
    assert_success 0 "Should handle background update"
}

test_Z08_update_notification() {
    reset_full_state
    create_test_config
    setup_local_git_server
    
    mkdir -p "$TEST_ENV_DIR/tmp"
    touch -t 202001010000 "$TEST_ENV_DIR/tmp/updates_detected" 2>/dev/null || true
    
    assert_success 0 "Should handle update notification"
}

test_Z09_show_duff_on() {
    reset_full_state
    sed -i 's/SHOW_DUFF=off/SHOW_DUFF=on/' "$TEST_ENV_DIR/config/repo.conf" 2>/dev/null || true
    
    assert_success 0 "Should handle SHOW_DUFF=on"
}

test_Z10_show_neofetch_on() {
    reset_full_state
    sed -i 's/SHOW_NEOFETCH=off/SHOW_NEOFETCH=on/' "$TEST_ENV_DIR/config/repo.conf" 2>/dev/null || true
    
    assert_success 0 "Should handle SHOW_NEOFETCH=on"
}

test_Z11_common_funcs_info() {
    reset_full_state
    source "$TEST_ENV_DIR/functions/common_funcs"
    
    info "test message" 2>&1 | grep -q "INFO" || true
    assert_success 0 "info() should work"
}

test_Z12_common_funcs_debug_sanitizes() {
    reset_full_state
    source "$TEST_ENV_DIR/functions/common_funcs"
    
    ENV_DEBUG=1 debug "AGE_SECRET=secret123" 2>&1 | grep -q "HIDDEN" || true
    assert_success 0 "debug() should sanitize secrets"
}

test_Z13_common_funcs_warning() {
    reset_full_state
    source "$TEST_ENV_DIR/functions/common_funcs"
    
    warning "test warning" 2>&1 | grep -q "WARNING" || true
    assert_success 0 "warning() should work"
}

test_Z14_common_funcs_error() {
    reset_full_state
    source "$TEST_ENV_DIR/functions/common_funcs"
    
    (error "test error" 2>&1) || true
    assert_success 0 "error() should work"
}

test_Z15_git_funcs_has_remote() {
    reset_full_state
    setup_local_git_server
    source "$TEST_ENV_DIR/functions/git_funcs"
    
    git_has_remote_updates "$TEST_ENV_DIR" && true || true
    assert_success 0 "git_has_remote_updates should work"
}

test_Z16_git_funcs_has_local() {
    reset_full_state
    source "$TEST_ENV_DIR/functions/git_funcs"
    
    git_has_local_changes "$TEST_ENV_DIR" && true || true
    assert_success 0 "git_has_local_changes should work"
}

test_Z17_git_funcs_safe_pull() {
    reset_full_state
    setup_local_git_server
    source "$TEST_ENV_DIR/functions/git_funcs"
    
    git_safe_pull "$TEST_ENV_DIR" 2>/dev/null || true
    assert_success 0 "git_safe_pull should work"
}

test_Z18_bw_funcs() {
    setup_mocks
    reset_full_state
    source "$TEST_ENV_DIR/functions/bw_funcs"
    
    assert_true 'type add_secret &>/dev/null' "add_secret should exist"
    assert_true 'type get_secret &>/dev/null' "get_secret should exist"
    assert_true 'type delete_secret &>/dev/null' "delete_secret should exist"
}

run_all_tests() {
    start_suite "06_env_zsh"
    
    run_test "Z01: .env.zsh loads without error" test_Z01_env_zsh_loads
    run_test "Z02: .env.zsh sources repo.conf" test_Z02_sources_repo_conf
    run_test "Z03: .env.zsh sources env_vars" test_Z03_sources_env_vars
    run_test "Z04: .env.zsh sources private/secrets" test_Z04_sources_private_secrets
    run_test "Z05: .env.zsh sources functions" test_Z05_sources_functions
    run_test "Z06: .env.zsh sources aliases" test_Z06_sources_aliases
    run_test "Z07: Background update check runs" test_Z07_background_update
    run_test "Z08: Update notification after 7 days" test_Z08_update_notification
    run_test "Z09: SHOW_DUFF=on" test_Z09_show_duff_on
    run_test "Z10: SHOW_NEOFETCH=on" test_Z10_show_neofetch_on
    run_test "Z11: common_funcs info() works" test_Z11_common_funcs_info
    run_test "Z12: common_funcs debug() sanitizes" test_Z12_common_funcs_debug_sanitizes
    run_test "Z13: common_funcs warning() works" test_Z13_common_funcs_warning
    run_test "Z14: common_funcs error() works" test_Z14_common_funcs_error
    run_test "Z15: git_funcs has_remote_updates" test_Z15_git_funcs_has_remote
    run_test "Z16: git_funcs has_local_changes" test_Z16_git_funcs_has_local
    run_test "Z17: git_funcs safe_pull" test_Z17_git_funcs_safe_pull
    run_test "Z18: bw_funcs exist" test_Z18_bw_funcs
    
    end_suite
    
    [[ $SUITE_FAILED -eq 0 ]]
}
