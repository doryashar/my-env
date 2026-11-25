#!/bin/bash

source "$SCRIPT_DIR/lib/test_framework.sh"
source "$SCRIPT_DIR/lib/state_manager.sh"
source "$SCRIPT_DIR/lib/mocks.sh"

# Every test imports the real sync_encrypted.sh functions via
# load_sync_encrypted (state_manager.sh): sourcing the file directly would
# run its top-level main() in the test process and kill the suite.

test_X01_command_exists() {
    reset_full_state
    load_sync_encrypted

    assert_true 'type command_exists &>/dev/null' "Function should exist"
}

test_X02_ensure_age_installed() {
    setup_mocks
    reset_full_state
    load_sync_encrypted

    local rc=0
    ensure_age_installed || rc=$?
    assert_success "$rc" "ensure_age_installed succeeds with age available"
    assert_equals "$MOCK_AGE_DIR/age" "$(command -v age)" \
        "age resolves to the provided binary, nothing was installed"
}

test_X03_encrypt_file_single() {
    setup_mocks
    reset_full_state

    echo "secret data" > "$TEST_ENV_DIR/tmp/plaintext.txt"
    echo "recipient" > "$TEST_ENV_DIR/tmp/recipients"

    load_sync_encrypted
    RECIPIENTS_FILE="$TEST_ENV_DIR/tmp/recipients"
    local rc=0
    encrypt_file "$TEST_ENV_DIR/tmp/plaintext.txt" "$TEST_ENV_DIR/tmp/encrypted.age" 2>/dev/null || rc=$?

    assert_success "$rc" "encrypt_file succeeds"
    assert_file_exists "$TEST_ENV_DIR/tmp/encrypted.age" "Should create encrypted file"
    assert_file_contains "$TEST_ENV_DIR/tmp/encrypted.age" "age-encryption.org/v1" \
        "encrypted file carries the age header"
}

test_X04_encrypt_file_directory() {
    setup_mocks
    reset_full_state

    mkdir -p "$TEST_ENV_DIR/tmp/secrets"
    echo "secret1" > "$TEST_ENV_DIR/tmp/secrets/file1.txt"
    echo "recipient" > "$TEST_ENV_DIR/tmp/recipients"

    load_sync_encrypted
    RECIPIENTS_FILE="$TEST_ENV_DIR/tmp/recipients"
    local rc=0
    encrypt_file "$TEST_ENV_DIR/tmp/secrets" "$TEST_ENV_DIR/tmp/secrets.age" 2>/dev/null || rc=$?

    assert_success "$rc" "encrypt_file succeeds on a directory"
    assert_file_exists "$TEST_ENV_DIR/tmp/secrets.age" "Should encrypt directory"
}

test_X05_decrypt_file() {
    setup_mocks
    reset_full_state

    echo "age-encryption.org/v1" > "$TEST_ENV_DIR/tmp/encrypted.age"
    echo "decrypted content" >> "$TEST_ENV_DIR/tmp/encrypted.age"

    load_sync_encrypted
    AGE_SECRET="test-key"
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    local rc=0
    decrypt_file "$TEST_ENV_DIR/tmp/encrypted.age" "$TEST_ENV_DIR/tmp/decrypted.txt" 2>/dev/null || rc=$?

    assert_success "$rc" "decrypt_file succeeds"
    assert_file_exists "$TEST_ENV_DIR/tmp/decrypted.txt" "Should decrypt file"
    assert_file_contains "$TEST_ENV_DIR/tmp/decrypted.txt" "decrypted content" \
        "decrypted content is correct"
}

test_X06_decrypt_file_tar() {
    setup_mocks
    reset_full_state

    # Encrypted directory payload: the age header line followed by a tar
    # stream. The tar must not contain the .age file itself: a
    # self-referential stream would be truncated by the mock age's
    # line-based decrypt.
    mkdir -p "$TEST_ENV_DIR/tmp/tarsrc"
    echo "archived content" > "$TEST_ENV_DIR/tmp/tarsrc/inner.txt"
    {
        echo "age-encryption.org/v1"
        tar -cf - -C "$TEST_ENV_DIR/tmp/tarsrc" .
    } > "$TEST_ENV_DIR/tmp/archive.age"

    load_sync_encrypted
    AGE_SECRET="test-key"
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    local rc=0
    decrypt_file "$TEST_ENV_DIR/tmp/archive.age" "$TEST_ENV_DIR/tmp/extracted" 2>/dev/null || rc=$?

    assert_success "$rc" "decrypt_file succeeds on a tar archive"
    assert_dir_exists "$TEST_ENV_DIR/tmp/extracted" "Should extract tar"
    assert_file_contains "$TEST_ENV_DIR/tmp/extracted/inner.txt" "archived content" \
        "the archived file is extracted"
}

test_X07_encrypt_recursive() {
    setup_mocks
    reset_full_state

    mkdir -p "$TEST_ENV_DIR/tmp/plain/dir"
    echo "file1" > "$TEST_ENV_DIR/tmp/plain/file1.txt"
    echo "file2" > "$TEST_ENV_DIR/tmp/plain/dir/file2.txt"
    echo "recipient" > "$TEST_ENV_DIR/tmp/recipients"

    load_sync_encrypted
    RECIPIENTS_FILE="$TEST_ENV_DIR/tmp/recipients"
    local rc=0
    encrypt_recursive "$TEST_ENV_DIR/tmp/plain" "$TEST_ENV_DIR/tmp/encrypted" 2>/dev/null || rc=$?

    assert_success "$rc" "encrypt_recursive succeeds"
    assert_file_exists "$TEST_ENV_DIR/tmp/encrypted/file1.txt.age" "Should encrypt recursively"
    assert_file_exists "$TEST_ENV_DIR/tmp/encrypted/dir/file2.txt.age" \
        "nested files are encrypted"
}

test_X08_decrypt_recursive() {
    setup_mocks
    reset_full_state

    mkdir -p "$TEST_ENV_DIR/tmp/encrypted"
    echo "age-encryption.org/v1" > "$TEST_ENV_DIR/tmp/encrypted/file1.age"
    echo "content1" >> "$TEST_ENV_DIR/tmp/encrypted/file1.age"
    echo "age-encryption.org/v1" > "$TEST_ENV_DIR/tmp/encrypted/file2.age"
    echo "content2" >> "$TEST_ENV_DIR/tmp/encrypted/file2.age"

    load_sync_encrypted
    AGE_SECRET="test-key"
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    local rc=0
    decrypt_recursive "$TEST_ENV_DIR/tmp/encrypted" "$TEST_ENV_DIR/tmp/decrypted" 2>/dev/null || rc=$?

    assert_success "$rc" "decrypt_recursive succeeds"
    assert_file_exists "$TEST_ENV_DIR/tmp/decrypted/file1" "Should decrypt recursively"
    assert_file_contains "$TEST_ENV_DIR/tmp/decrypted/file2" "content2" \
        "second file decrypts correctly"
}

test_X09_hashit_generates() {
    reset_full_state

    mkdir -p "$TEST_ENV_DIR/tmp/data"
    echo "data" > "$TEST_ENV_DIR/tmp/data/file.txt"

    load_sync_encrypted
    local rc=0
    hashit "$TEST_ENV_DIR/tmp/data" "$TEST_ENV_DIR/tmp/hash.txt" 2>/dev/null || rc=$?

    assert_success "$rc" "hashit succeeds"
    assert_file_exists "$TEST_ENV_DIR/tmp/hash.txt" "Should generate hash file"
    assert_file_contains "$TEST_ENV_DIR/tmp/hash.txt" "file.txt" \
        "hash file lists the hashed file"
}

test_X10_has_changed_detects() {
    reset_full_state

    mkdir -p "$TEST_ENV_DIR/tmp/data"
    echo "data" > "$TEST_ENV_DIR/tmp/data/file.txt"

    load_sync_encrypted
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    hashit "$TEST_ENV_DIR/tmp/data" "$TEST_ENV_DIR/tmp/hash.txt" 2>/dev/null

    local rc=0
    has_changed "$TEST_ENV_DIR/tmp/data" "$TEST_ENV_DIR/tmp/hash.txt" || rc=$?
    assert_success "$rc" "unchanged directory reports no change"

    echo "modified" > "$TEST_ENV_DIR/tmp/data/file.txt"
    rc=0
    has_changed "$TEST_ENV_DIR/tmp/data" "$TEST_ENV_DIR/tmp/hash.txt" || rc=$?
    assert_failure "$rc" "Should detect changes"
}

test_X11_has_changed_new_hash() {
    reset_full_state

    mkdir -p "$TEST_ENV_DIR/tmp/data"
    echo "data" > "$TEST_ENV_DIR/tmp/data/file.txt"

    load_sync_encrypted
    TEMP_DIR="$TEST_ENV_DIR/tmp"

    local out rc=0
    out=$(has_changed "$TEST_ENV_DIR/tmp/data" "$TEST_ENV_DIR/tmp/nonexistent_hash.txt" 2>&1) || rc=$?
    assert_failure "$rc" "Should return changed for a missing hash file"
    assert_contains "$out" "No previous hash file found" "reason is reported"
}

test_X12_merge_remote_only() {
    reset_full_state

    mkdir -p "$TEST_ENV_DIR/tmp/remote"
    mkdir -p "$TEST_ENV_DIR/tmp/local"
    mkdir -p "$TEST_ENV_DIR/tmp/merged"
    echo "remote content" > "$TEST_ENV_DIR/tmp/remote/file.txt"

    load_sync_encrypted
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    local rc=0
    merge_changes "$TEST_ENV_DIR/tmp/remote" "$TEST_ENV_DIR/tmp/local" "$TEST_ENV_DIR/tmp/merged" 2>/dev/null || rc=$?

    assert_success "$rc" "merge_changes succeeds"
    assert_file_contains "$TEST_ENV_DIR/tmp/merged/file.txt" "remote content" "Should keep remote-only file"
}

test_X13_merge_local_only() {
    reset_full_state

    mkdir -p "$TEST_ENV_DIR/tmp/remote"
    mkdir -p "$TEST_ENV_DIR/tmp/local"
    mkdir -p "$TEST_ENV_DIR/tmp/merged"
    echo "local content" > "$TEST_ENV_DIR/tmp/local/file.txt"

    load_sync_encrypted
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    local rc=0
    merge_changes "$TEST_ENV_DIR/tmp/remote" "$TEST_ENV_DIR/tmp/local" "$TEST_ENV_DIR/tmp/merged" 2>/dev/null || rc=$?

    assert_success "$rc" "merge_changes succeeds"
    assert_file_contains "$TEST_ENV_DIR/tmp/merged/file.txt" "local content" "Should keep local-only file"
}

test_X14_merge_identical() {
    reset_full_state

    mkdir -p "$TEST_ENV_DIR/tmp/remote"
    mkdir -p "$TEST_ENV_DIR/tmp/local"
    mkdir -p "$TEST_ENV_DIR/tmp/merged"
    echo "same content" > "$TEST_ENV_DIR/tmp/remote/file.txt"
    echo "same content" > "$TEST_ENV_DIR/tmp/local/file.txt"

    load_sync_encrypted
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    local rc=0
    merge_changes "$TEST_ENV_DIR/tmp/remote" "$TEST_ENV_DIR/tmp/local" "$TEST_ENV_DIR/tmp/merged" 2>/dev/null || rc=$?

    assert_success "$rc" "merge_changes succeeds"
    assert_file_contains "$TEST_ENV_DIR/tmp/merged/file.txt" "same content" "Should handle identical files"
}

test_X15_merge_conflicts() {
    skip_test "Interactive merge - tested in integration"
}

test_X16_check_remote_ssh_url() {
    reset_full_state
    load_sync_encrypted

    local url="git@github.com:owner/repo.git"
    local rc=0
    parse_repo_url "$url" || rc=$?
    assert_success "$rc" "parses an SSH-style GitHub URL"
    assert_equals "owner" "$REPO_OWNER" "Should parse owner"
    assert_equals "repo" "$REPO_NAME" "Should parse repo"
}

test_X17_check_remote_https_url() {
    reset_full_state
    load_sync_encrypted

    local url="https://github.com/owner/repo.git"
    local rc=0
    parse_repo_url "$url" || rc=$?
    assert_success "$rc" "parses an HTTPS GitHub URL"
    assert_equals "owner" "$REPO_OWNER" "Should parse owner from HTTPS"
    assert_equals "repo" "$REPO_NAME" "Should parse repo name without .git"
}

test_X18_show_changed_files() {
    reset_full_state
    load_sync_encrypted

    assert_true 'type show_changed_files_and_confirm &>/dev/null' "Function should exist"
}

test_X19_cleanup() {
    reset_full_state

    mkdir -p "$TEST_ENV_DIR/tmp/cleanup_test"
    echo "temp" > "$TEST_ENV_DIR/tmp/cleanup_test/file.txt"

    load_sync_encrypted
    TEMP_DIR="$TEST_ENV_DIR/tmp/cleanup_test"
    local rc=0
    cleanup || rc=$?

    assert_success "$rc" "cleanup runs"
    assert_dir_not_exists "$TEST_ENV_DIR/tmp/cleanup_test" "Should cleanup temp dir"
}

test_X20_main_no_changes() {
    setup_mocks
    reset_full_state
    load_sync_encrypted

    assert_true 'type main &>/dev/null' "main function should exist"
}

run_all_tests() {
    start_suite "04_sync_encrypted"

    run_test "X01: command_exists available" test_X01_command_exists
    run_test "X02: ensure_age_installed with mock age" test_X02_ensure_age_installed
    run_test "X03: encrypt_file single file" test_X03_encrypt_file_single
    run_test "X04: encrypt_file directory" test_X04_encrypt_file_directory
    run_test "X05: decrypt_file" test_X05_decrypt_file
    run_test "X06: decrypt_file tar archive" test_X06_decrypt_file_tar
    run_test "X07: encrypt_recursive" test_X07_encrypt_recursive
    run_test "X08: decrypt_recursive" test_X08_decrypt_recursive
    run_test "X09: hashit generates hash file" test_X09_hashit_generates
    run_test "X10: has_changed detects changes" test_X10_has_changed_detects
    run_test "X11: has_changed new hash" test_X11_has_changed_new_hash
    run_test "X12: merge remote only" test_X12_merge_remote_only
    run_test "X13: merge local only" test_X13_merge_local_only
    run_test "X14: merge identical" test_X14_merge_identical
    run_test "X15: merge conflicts" test_X15_merge_conflicts
    run_test "X16: check remote ssh url" test_X16_check_remote_ssh_url
    run_test "X17: check remote https url" test_X17_check_remote_https_url
    run_test "X18: show_changed_files exists" test_X18_show_changed_files
    run_test "X19: cleanup removes temp dir" test_X19_cleanup
    run_test "X20: main function defined" test_X20_main_no_changes

    end_suite

    [[ $SUITE_FAILED -eq 0 ]]
}
