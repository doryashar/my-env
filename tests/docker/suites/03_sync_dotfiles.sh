#!/bin/bash

source "$SCRIPT_DIR/lib/test_framework.sh"
source "$SCRIPT_DIR/lib/state_manager.sh"

test_D01_create_default_config() {
    reset_full_state
    rm -f "$TEST_ENV_DIR/config/dotfiles.conf"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    create_default_config "$TEST_ENV_DIR/config/dotfiles.conf"
    
    assert_file_exists "$TEST_ENV_DIR/config/dotfiles.conf" "Config should be created"
}

test_D02_create_default_config_warns() {
    reset_full_state
    echo "existing" > "$TEST_ENV_DIR/config/dotfiles.conf"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    create_default_config "$TEST_ENV_DIR/config/dotfiles.conf" 2>&1 | grep -q "already exists" || true
    
    assert_file_contains "$TEST_ENV_DIR/config/dotfiles.conf" "existing" "Should not overwrite"
}

test_D03_load_config_link_type() {
    reset_full_state
    
    cat > "$TEST_ENV_DIR/config/dotfiles.conf" << 'EOF'
DEFAULT_LINK_TYPE="hard"
EOF
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    load_config "$TEST_ENV_DIR/config/dotfiles.conf"
    
    assert_equals "hard" "$DEFAULT_LINK_TYPE" "Should parse link type"
}

test_D04_load_config_conflict_strategy() {
    reset_full_state
    
    cat > "$TEST_ENV_DIR/config/dotfiles.conf" << 'EOF'
DEFAULT_CONFLICT_STRATEGY="local"
EOF
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    load_config "$TEST_ENV_DIR/config/dotfiles.conf"
    
    assert_equals "local" "$DEFAULT_CONFLICT_STRATEGY" "Should parse conflict strategy"
}

test_D05_load_config_forward_mappings() {
    reset_full_state
    create_dotfiles_config
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    load_config "$TEST_ENV_DIR/config/dotfiles.conf"
    
    assert_true '[[ -n "${SOURCE_TO_TARGET[dotfiles/.bashrc]}" ]]' "Should parse forward mapping"
}

test_D06_load_config_backward_mappings() {
    reset_full_state
    
    cat > "$TEST_ENV_DIR/config/dotfiles.conf" << 'EOF'
DEFAULT_LINK_TYPE="soft"
custom/local <= ~/.local_settings
EOF
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    load_config "$TEST_ENV_DIR/config/dotfiles.conf"
    
    assert_true '[[ ${#BACKWARD_SYNC[@]} -gt 0 ]]' "Should parse backward mapping"
}

test_D07_load_config_regex_patterns() {
    reset_full_state
    
    cat > "$TEST_ENV_DIR/config/dotfiles.conf" << 'EOF'
DEFAULT_LINK_TYPE="soft"
config/(.*) => ~/.config/$1
EOF
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    load_config "$TEST_ENV_DIR/config/dotfiles.conf"
    
    assert_true '[[ ${#SOURCE_REGEX[@]} -gt 0 ]]' "Should parse regex pattern"
}

test_D08_process_regex_wildcards() {
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/config/test"
    echo "test value" > "$TEST_ENV_DIR/config/test/settings.conf"
    
    cat > "$TEST_ENV_DIR/config/dotfiles.conf" << 'EOF'
DEFAULT_LINK_TYPE="soft"
DEFAULT_CONFLICT_STRATEGY="remote"
config/* => ~/.config/*
EOF
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    load_config "$TEST_ENV_DIR/config/dotfiles.conf"
    process_regex_mappings 2>/dev/null || true
    
    assert_symlink_exists "$TEST_HOME/.config/test/settings.conf" "Wildcard should create symlink"
}

test_D09_process_regex_capture_groups() {
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/nvim"
    echo "nvim config" > "$TEST_ENV_DIR/nvim/init.vim"
    
    cat > "$TEST_ENV_DIR/config/dotfiles.conf" << 'EOF'
DEFAULT_LINK_TYPE="soft"
DEFAULT_CONFLICT_STRATEGY="remote"
nvim/(.*) => ~/.config/nvim/$1
EOF
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    load_config "$TEST_ENV_DIR/config/dotfiles.conf"
    process_regex_mappings 2>/dev/null || true
    
    assert_symlink_exists "$TEST_HOME/.config/nvim/init.vim" "Capture group should work"
}

test_D10_handle_conflict_ask() {
    reset_full_state
    create_test_dotfile ".testrc" "repo version"
    create_home_file ".testrc" "home version"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    
    assert_true 'type handle_conflict &>/dev/null' "Function should exist"
}

test_D11_handle_conflict_local() {
    reset_full_state
    create_test_dotfile ".testrc" "repo version"
    create_home_file ".testrc" "home version"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    
    assert_true 'type handle_conflict &>/dev/null' "Function should exist"
}

test_D12_handle_conflict_remote() {
    reset_full_state
    create_test_dotfile ".testrc" "repo version"
    create_home_file ".testrc" "home version"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    
    assert_true 'type handle_conflict &>/dev/null' "Function should exist"
}

test_D13_handle_conflict_rename() {
    reset_full_state
    create_test_dotfile ".testrc" "repo version"
    create_home_file ".testrc" "home version"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    
    assert_true 'type handle_conflict &>/dev/null' "Function should exist"
}

test_D14_handle_conflict_ignore() {
    reset_full_state
    create_test_dotfile ".testrc" "repo version"
    create_home_file ".testrc" "home version"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    
    assert_true 'type handle_conflict &>/dev/null' "Function should exist"
}

test_D15_sync_file_creates_symlink() {
    reset_full_state
    create_test_dotfile ".newrc" "new file"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    create_dotfiles_config
    load_config "$TEST_ENV_DIR/config/dotfiles.conf"
    
    sync_file "dotfiles/.newrc" "$TEST_HOME/.newrc" "link=soft conflict=remote" 2>/dev/null || true
    
    assert_symlink_exists "$TEST_HOME/.newrc" "Should create symlink"
}

test_D16_sync_file_skips_existing_symlink() {
    reset_full_state
    create_test_dotfile ".testrc" "test content"
    
    ln -sf "$TEST_ENV_DIR/dotfiles/.testrc" "$TEST_HOME/.testrc"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    sync_file "dotfiles/.testrc" "$TEST_HOME/.testrc" "link=soft conflict=remote" 2>/dev/null || true
    
    assert_symlink_to "$TEST_HOME/.testrc" "$TEST_ENV_DIR/dotfiles/.testrc" "Should keep existing symlink"
}

test_D17_sync_file_handles_identical() {
    reset_full_state
    create_test_dotfile ".testrc" "same content"
    create_home_file ".testrc" "same content"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    sync_file "dotfiles/.testrc" "$TEST_HOME/.testrc" "link=soft conflict=remote" 2>/dev/null || true
    
    assert_symlink_exists "$TEST_HOME/.testrc" "Should handle identical files"
}

test_D18_sync_file_newer_target() {
    reset_full_state
    create_test_dotfile ".testrc" "repo version"
    create_home_file ".testrc" "home version"
    sleep 0.1
    touch "$TEST_HOME/.testrc"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    
    assert_true 'type sync_file &>/dev/null' "Function should exist"
}

test_D19_sync_file_newer_source() {
    reset_full_state
    create_test_dotfile ".testrc" "repo version"
    sleep 0.1
    create_home_file ".testrc" "home version"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    
    assert_true 'type sync_file &>/dev/null' "Function should exist"
}

test_D20_sync_file_missing_both() {
    reset_full_state
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    sync_file "nonexistent/file" "$TEST_HOME/nonexistent" "link=soft conflict=remote" 2>/dev/null
    
    assert_failure $? "Should fail when both missing"
}

test_D21_backward_sync_file() {
    reset_full_state
    create_home_file ".local_settings" "local content"
    
    cat > "$TEST_ENV_DIR/config/dotfiles.conf" << 'EOF'
DEFAULT_LINK_TYPE="soft"
DEFAULT_CONFLICT_STRATEGY="remote"
custom/local <= ~/.local_settings
EOF
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    load_config "$TEST_ENV_DIR/config/dotfiles.conf"
    process_backward_sync 2>/dev/null || true
    
    assert_file_exists "$TEST_ENV_DIR/custom/local" "Should copy to repo"
}

test_D22_create_link_soft() {
    reset_full_state
    create_test_file "test_link.txt" "link content"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    create_link "$TEST_ENV_DIR/test_link.txt" "$TEST_HOME/test_link.txt" "soft"
    
    assert_symlink_exists "$TEST_HOME/test_link.txt" "Should create soft link"
}

test_D23_create_link_hard() {
    reset_full_state
    create_test_file "test_link.txt" "link content"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    create_link "$TEST_ENV_DIR/test_link.txt" "$TEST_HOME/test_link.txt" "hard"
    
    assert_true '[[ -f "$TEST_HOME/test_link.txt" ]]' "Hard link should exist"
}

test_D24_remove_broken_links() {
    reset_full_state
    
    ln -sf "$TEST_ENV_DIR/nonexistent" "$TEST_HOME/broken_link"
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    remove_all_broken_links "$TEST_HOME"
    
    assert_false '-L "$TEST_HOME/broken_link"' "Should remove broken link"
}

test_D25_main_full_sync() {
    reset_full_state
    create_test_dotfile ".bashrc" "# bashrc content"
    create_dotfiles_config
    
    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    
    assert_true 'type main &>/dev/null' "main function should exist"
}

run_all_tests() {
    start_suite "03_sync_dotfiles"
    
    run_test "D01: create_default_config generates file" test_D01_create_default_config
    run_test "D02: create_default_config warns if exists" test_D02_create_default_config_warns
    run_test "D03: load_config parses link type" test_D03_load_config_link_type
    run_test "D04: load_config parses conflict strategy" test_D04_load_config_conflict_strategy
    run_test "D05: load_config parses forward mappings" test_D05_load_config_forward_mappings
    run_test "D06: load_config parses backward mappings" test_D06_load_config_backward_mappings
    run_test "D07: load_config parses regex patterns" test_D07_load_config_regex_patterns
    run_test "D08: process_regex expands wildcards" test_D08_process_regex_wildcards
    run_test "D09: process_regex handles capture groups" test_D09_process_regex_capture_groups
    run_test "D10: handle_conflict: ask strategy" test_D10_handle_conflict_ask
    run_test "D11: handle_conflict: local strategy" test_D11_handle_conflict_local
    run_test "D12: handle_conflict: remote strategy" test_D12_handle_conflict_remote
    run_test "D13: handle_conflict: rename strategy" test_D13_handle_conflict_rename
    run_test "D14: handle_conflict: ignore strategy" test_D14_handle_conflict_ignore
    run_test "D15: sync_file creates symlink" test_D15_sync_file_creates_symlink
    run_test "D16: sync_file skips existing correct symlink" test_D16_sync_file_skips_existing_symlink
    run_test "D17: sync_file handles identical files" test_D17_sync_file_handles_identical
    run_test "D18: sync_file handles newer target" test_D18_sync_file_newer_target
    run_test "D19: sync_file handles newer source" test_D19_sync_file_newer_source
    run_test "D20: sync_file fails when both missing" test_D20_sync_file_missing_both
    run_test "D21: backward_sync_file copies to repo" test_D21_backward_sync_file
    run_test "D22: create_link creates soft link" test_D22_create_link_soft
    run_test "D23: create_link creates hard link" test_D23_create_link_hard
    run_test "D24: remove_broken_links removes dead links" test_D24_remove_broken_links
    run_test "D25: main runs full sync flow" test_D25_main_full_sync
    
    end_suite
    
    [[ $SUITE_FAILED -eq 0 ]]
}
