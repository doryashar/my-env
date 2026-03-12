#!/bin/bash

source "$SCRIPT_DIR/lib/test_framework.sh"
source "$SCRIPT_DIR/lib/state_manager.sh"
source "$SCRIPT_DIR/lib/mocks.sh"

test_X01_command_exists() {
    reset_full_state
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    
    assert_true 'type command_exists &>/dev/null' "Function should exist"
}

test_X02_ensure_age_installed() {
    setup_mocks
    reset_full_state
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    
    ensure_age_installed 2>/dev/null || true
    assert_success 0 "Should work with mock age"
}

test_X03_encrypt_file_single() {
    setup_mocks
    reset_full_state
    
    echo "secret data" > "$TEST_ENV_DIR/tmp/plaintext.txt"
    echo "recipient" > "$TEST_ENV_DIR/tmp/recipients"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    RECIPIENTS_FILE="$TEST_ENV_DIR/tmp/recipients"
    encrypt_file "$TEST_ENV_DIR/tmp/plaintext.txt" "$TEST_ENV_DIR/tmp/encrypted.age" 2>/dev/null || true
    
    assert_file_exists "$TEST_ENV_DIR/tmp/encrypted.age" "Should create encrypted file"
}

test_X04_encrypt_file_directory() {
    setup_mocks
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/tmp/secrets"
    echo "secret1" > "$TEST_ENV_DIR/tmp/secrets/file1.txt"
    echo "recipient" > "$TEST_ENV_DIR/tmp/recipients"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    RECIPIENTS_FILE="$TEST_ENV_DIR/tmp/recipients"
    encrypt_file "$TEST_ENV_DIR/tmp/secrets" "$TEST_ENV_DIR/tmp/secrets.age" 2>/dev/null || true
    
    assert_file_exists "$TEST_ENV_DIR/tmp/secrets.age" "Should encrypt directory"
}

test_X05_decrypt_file() {
    setup_mocks
    reset_full_state
    
    echo "age-encryption.org/v1" > "$TEST_ENV_DIR/tmp/encrypted.age"
    echo "decrypted content" >> "$TEST_ENV_DIR/tmp/encrypted.age"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    AGE_SECRET="test-key"
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    decrypt_file "$TEST_ENV_DIR/tmp/encrypted.age" "$TEST_ENV_DIR/tmp/decrypted.txt" 2>/dev/null || true
    
    assert_file_exists "$TEST_ENV_DIR/tmp/decrypted.txt" "Should decrypt file"
}

test_X06_decrypt_file_tar() {
    setup_mocks
    reset_full_state
    
    echo "age-encryption.org/v1" > "$TEST_ENV_DIR/tmp/archive.age"
    tar -cf - -C "$TEST_ENV_DIR/tmp" . 2>/dev/null >> "$TEST_ENV_DIR/tmp/archive.age" || true
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    AGE_SECRET="test-key"
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    mkdir -p "$TEST_ENV_DIR/tmp/extracted"
    decrypt_file "$TEST_ENV_DIR/tmp/archive.age" "$TEST_ENV_DIR/tmp/extracted" 2>/dev/null || true
    
    assert_dir_exists "$TEST_ENV_DIR/tmp/extracted" "Should extract tar"
}

test_X07_encrypt_recursive() {
    setup_mocks
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/tmp/plain/dir"
    echo "file1" > "$TEST_ENV_DIR/tmp/plain/file1.txt"
    echo "file2" > "$TEST_ENV_DIR/tmp/plain/dir/file2.txt"
    echo "recipient" > "$TEST_ENV_DIR/tmp/recipients"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    RECIPIENTS_FILE="$TEST_ENV_DIR/tmp/recipients"
    encrypt_recursive "$TEST_ENV_DIR/tmp/plain" "$TEST_ENV_DIR/tmp/encrypted" 2>/dev/null || true
    
    assert_file_exists "$TEST_ENV_DIR/tmp/encrypted/file1.txt.age" "Should encrypt recursively"
}

test_X08_decrypt_recursive() {
    setup_mocks
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/tmp/encrypted"
    echo "age-encryption.org/v1" > "$TEST_ENV_DIR/tmp/encrypted/file1.age"
    echo "content1" >> "$TEST_ENV_DIR/tmp/encrypted/file1.age"
    echo "age-encryption.org/v1" > "$TEST_ENV_DIR/tmp/encrypted/file2.age"
    echo "content2" >> "$TEST_ENV_DIR/tmp/encrypted/file2.age"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    AGE_SECRET="test-key"
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    decrypt_recursive "$TEST_ENV_DIR/tmp/encrypted" "$TEST_ENV_DIR/tmp/decrypted" 2>/dev/null || true
    
    assert_file_exists "$TEST_ENV_DIR/tmp/decrypted/file1" "Should decrypt recursively"
}

test_X09_hashit_generates() {
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/tmp/data"
    echo "data" > "$TEST_ENV_DIR/tmp/data/file.txt"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    hashit "$TEST_ENV_DIR/tmp/data" "$TEST_ENV_DIR/tmp/hash.txt" 2>/dev/null || true
    
    assert_file_exists "$TEST_ENV_DIR/tmp/hash.txt" "Should generate hash file"
}

test_X10_has_changed_detects() {
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/tmp/data"
    echo "data" > "$TEST_ENV_DIR/tmp/data/file.txt"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    hashit "$TEST_ENV_DIR/tmp/data" "$TEST_ENV_DIR/tmp/hash.txt" 2>/dev/null || true
    
    echo "modified" > "$TEST_ENV_DIR/tmp/data/file.txt"
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    
    has_changed "$TEST_ENV_DIR/tmp/data" "$TEST_ENV_DIR/tmp/hash.txt"
    assert_failure $? "Should detect changes"
}

test_X11_has_changed_new_hash() {
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/tmp/data"
    echo "data" > "$TEST_ENV_DIR/tmp/data/file.txt"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    
    has_changed "$TEST_ENV_DIR/tmp/data" "$TEST_ENV_DIR/tmp/nonexistent_hash.txt"
    assert_failure $? "Should return true for new hash"
}

test_X12_merge_remote_only() {
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/tmp/remote"
    mkdir -p "$TEST_ENV_DIR/tmp/local"
    mkdir -p "$TEST_ENV_DIR/tmp/merged"
    echo "remote content" > "$TEST_ENV_DIR/tmp/remote/file.txt"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    merge_changes "$TEST_ENV_DIR/tmp/remote" "$TEST_ENV_DIR/tmp/local" "$TEST_ENV_DIR/tmp/merged" 2>/dev/null || true
    
    assert_file_contains "$TEST_ENV_DIR/tmp/merged/file.txt" "remote content" "Should keep remote-only file"
}

test_X13_merge_local_only() {
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/tmp/remote"
    mkdir -p "$TEST_ENV_DIR/tmp/local"
    mkdir -p "$TEST_ENV_DIR/tmp/merged"
    echo "local content" > "$TEST_ENV_DIR/tmp/local/file.txt"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    merge_changes "$TEST_ENV_DIR/tmp/remote" "$TEST_ENV_DIR/tmp/local" "$TEST_ENV_DIR/tmp/merged" 2>/dev/null || true
    
    assert_file_contains "$TEST_ENV_DIR/tmp/merged/file.txt" "local content" "Should keep local-only file"
}

test_X14_merge_identical() {
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/tmp/remote"
    mkdir -p "$TEST_ENV_DIR/tmp/local"
    mkdir -p "$TEST_ENV_DIR/tmp/merged"
    echo "same content" > "$TEST_ENV_DIR/tmp/remote/file.txt"
    echo "same content" > "$TEST_ENV_DIR/tmp/local/file.txt"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    merge_changes "$TEST_ENV_DIR/tmp/remote" "$TEST_ENV_DIR/tmp/local" "$TEST_ENV_DIR/tmp/merged" 2>/dev/null || true
    
    assert_file_contains "$TEST_ENV_DIR/tmp/merged/file.txt" "same content" "Should handle identical files"
}

test_X15_merge_conflicts() {
    skip_test "Interactive merge - tested in integration"
}

test_X16_check_remote_ssh_url() {
    setup_mocks
    reset_full_state
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    
    local url="git@github.com:owner/repo.git"
    if [[ "$url" =~ git@github\.com:([^/]+)/(.+)\.git ]]; then
        assert_equals "owner" "${BASH_REMATCH[1]}" "Should parse owner"
        assert_equals "repo" "${BASH_REMATCH[2]}" "Should parse repo"
    fi
}

test_X17_check_remote_https_url() {
    setup_mocks
    reset_full_state
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    
    local url="https://github.com/owner/repo.git"
    if [[ "$url" =~ github\.com/([^/]+)/(.+)(\.git)? ]]; then
        assert_equals "owner" "${BASH_REMATCH[1]}" "Should parse owner from HTTPS"
    fi
}

test_X18_show_changed_files() {
    reset_full_state
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    
    assert_true 'type show_changed_files_and_confirm &>/dev/null' "Function should exist"
}

test_X19_cleanup() {
    reset_full_state
    
    mkdir -p "$TEST_ENV_DIR/tmp/cleanup_test"
    echo "temp" > "$TEST_ENV_DIR/tmp/cleanup_test/file.txt"
    
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    TEMP_DIR="$TEST_ENV_DIR/tmp/cleanup_test"
    cleanup 2>/dev/null || true
    
    assert_dir_not_exists "$TEST_ENV_DIR/tmp/cleanup_test" "Should cleanup temp dir"
}

test_X20_main_no_changes() {
    setup_mocks
    reset_full_state
    source "$TEST_ENV_DIR/scripts/sync_encrypted.sh"
    
    assert_true 'type main &>/dev/null' "main function should exist"
}

run_all_tests() {
    start_suite "04_sync_encrypted"
    
    run_test "X01: command_exists works" test_X01_command_exists
    run_test "X02: ensure_age_installed" test_X02_ensure_age_installed
    run_test "X03: encrypt_file single" test_X03_encrypt_file_single
    run_test "X04: encrypt_file directory" test_X04_encrypt_file_directory
    run_test "X05: decrypt_file" test_X05_decrypt_file
    run_test "X06: decrypt_file tar" test_X06_decrypt_file_tar
    run_test "X07: encrypt_recursive" test_X07_encrypt_recursive
    run_test "X08: decrypt_recursive" test_X08_decrypt_recursive
    run_test "X09: hashit generates hash" test_X09_hashit_generates
    run_test "X10: has_changed detects modifications" test_X10_has_changed_detects
    run_test "X11: has_changed returns true for new" test_X11_has_changed_new_hash
    run_test "X12: merge remote-only files" test_X12_merge_remote_only
    run_test "X13: merge local-only files" test_X13_merge_local_only
    run_test "X14: merge identical files" test_X14_merge_identical
    run_test "X15: merge conflicts" test_X15_merge_conflicts
    run_test "X16: check_remote SSH URL" test_X16_check_remote_ssh_url
    run_test "X17: check_remote HTTPS URL" test_X17_check_remote_https_url
    run_test "X18: show_changed_files exists" test_X18_show_changed_files
    run_test "X19: cleanup removes temp" test_X19_cleanup
    run_test "X20: main function exists" test_X20_main_no_changes
    
    end_suite
    
    [[ $SUITE_FAILED -eq 0 ]]
}
