#!/bin/bash

source "$SCRIPT_DIR/lib/test_framework.sh"
source "$SCRIPT_DIR/lib/state_manager.sh"
source "$SCRIPT_DIR/lib/mocks.sh"

test_I01_full_setup_from_scratch() {
    reset_full_state
    setup_mocks
    rm -f "$TEST_ENV_DIR/config/repo.conf"

    export REMOTE_URL="git@github.com:testowner/env-fork.git"
    export PRIVATE_URL="git@github.com:testowner/encrypted.git"
    export BW_EMAIL="test@example.com"

    local out rc=0
    out=$(bash "$TEST_ENV_DIR/scripts/setup.sh" </dev/null 2>&1) || rc=$?

    assert_success "$rc" "full setup completes in the container"
    assert_file_exists "$TEST_ENV_DIR/.env_installed" "installation marker written"
    assert_file_contains "$TEST_ENV_DIR/config/repo.conf" \
        'REMOTE_URL="git@github.com:testowner/env-fork.git"' "fork URL stored"
    assert_file_contains "$TEST_ENV_DIR/config/repo.conf" \
        'PRIVATE_URL="git@github.com:testowner/encrypted.git"' "private URL stored"
    # generate_config keeps the env-override form
    # export BW_EMAIL="${BW_EMAIL:-<value>}", so check the value on the
    # BW_EMAIL line rather than a bare literal.
    local bw_line
    bw_line=$(grep '^export BW_EMAIL=' "$TEST_ENV_DIR/config/repo.conf")
    assert_contains "$bw_line" "test@example.com" "BW email stored"
    assert_file_not_contains "$TEST_ENV_DIR/config/repo.conf" "YOUR_USER" \
        "no placeholders left in the config"

    local crontab_out
    crontab_out=$(crontab -l 2>/dev/null || true)
    assert_equals "" "$crontab_out" "the cron step installed nothing without a terminal"

    cp "$TEST_ENV_DIR/config/repo.conf" "$TEST_ROOT/repo.conf.i01"
}

test_I02_idempotent_setup() {
    # Same tree as I01: no reset, config already in place.
    local out rc=0
    out=$(bash "$TEST_ENV_DIR/scripts/setup.sh" </dev/null 2>&1) || rc=$?

    assert_success "$rc" "second setup run completes"
    assert_file_contains "$TEST_ENV_DIR/config/repo.conf" \
        'REMOTE_URL="git@github.com:testowner/env-fork.git"' "config preserved"
    assert_file_exists "$TEST_ROOT/repo.conf.i01" "the copy from I01 exists"
    local cmp_rc=0
    cmp -s "$TEST_ENV_DIR/config/repo.conf" "$TEST_ROOT/repo.conf.i01" || cmp_rc=$?
    assert_success "$cmp_rc" "repo.conf is byte-identical to after the first run"
}

test_I03_sync_env_help() {
    reset_full_state

    local out rc=0
    out=$(bash "$TEST_ENV_DIR/scripts/sync/sync_env.sh" --help 2>&1) || rc=$?
    assert_success "$rc" "sync_env.sh --help exits 0"
    assert_contains "$out" "Usage:" "prints a usage line"
}

test_I04_dotfiles_creates_links() {
    reset_full_state
    create_test_dotfile ".bashrc" "# bashrc content"
    create_dotfiles_config

    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"
    main "$TEST_ENV_DIR/config/dotfiles.conf" 2>/dev/null || true

    assert_symlink_exists "$TEST_HOME/.bashrc" "Dotfiles should create symlinks"
}

test_I05_local_changes_detected() {
    reset_full_state
    create_test_config
    setup_local_git_server

    source "$TEST_ENV_DIR/functions/git_funcs"

    local rc=0
    git_has_local_changes "$TEST_ENV_DIR" || rc=$?
    assert_equals 1 "$rc" "clean tree reports no local changes"

    echo "new setting=value" >> "$TEST_ENV_DIR/config/repo.conf"
    rc=0
    git_has_local_changes "$TEST_ENV_DIR" || rc=$?
    assert_equals 0 "$rc" "modified tracked file is detected"
}

test_I06_encrypted_sync_flow() {
    setup_mocks
    reset_full_state
    load_sync_encrypted

    # Real encrypt -> decrypt -> change-detection flow with the real
    # functions. (A full main() run needs a reachable GitHub SSH repo,
    # which a container does not have.)
    echo "recipient" > "$TEST_ENV_DIR/tmp/age-recipients"
    RECIPIENTS_FILE="$TEST_ENV_DIR/tmp/age-recipients"
    TEMP_DIR="$TEST_ENV_DIR/tmp"
    AGE_SECRET="AGE_SECRET_KEY_MOCK_12345"

    mkdir -p "$TEST_ENV_DIR/tmp/priv"
    echo "flow secret content" > "$TEST_ENV_DIR/tmp/priv/secret.txt"

    local rc=0
    encrypt_file "$TEST_ENV_DIR/tmp/priv/secret.txt" "$TEST_ENV_DIR/tmp/priv.age" || rc=$?
    assert_success "$rc" "real encrypt_file succeeds"
    assert_file_contains "$TEST_ENV_DIR/tmp/priv.age" "age-encryption.org/v1" \
        "the encrypted file carries the age header"

    rc=0
    decrypt_file "$TEST_ENV_DIR/tmp/priv.age" "$TEST_ENV_DIR/tmp/priv-roundtrip.txt" || rc=$?
    assert_success "$rc" "real decrypt_file succeeds"
    assert_file_contains "$TEST_ENV_DIR/tmp/priv-roundtrip.txt" "flow secret content" \
        "content round-trips through encrypt/decrypt"

    rc=0
    has_changed "$TEST_ENV_DIR/tmp/priv" "$TEST_ENV_DIR/tmp/priv.hash" || rc=$?
    assert_failure "$rc" "missing hash file counts as changed"

    hashit "$TEST_ENV_DIR/tmp/priv" "$TEST_ENV_DIR/tmp/priv.hash"
    rc=0
    has_changed "$TEST_ENV_DIR/tmp/priv" "$TEST_ENV_DIR/tmp/priv.hash" || rc=$?
    assert_success "$rc" "unchanged tree reports no change"

    echo "more" >> "$TEST_ENV_DIR/tmp/priv/secret.txt"
    rc=0
    has_changed "$TEST_ENV_DIR/tmp/priv" "$TEST_ENV_DIR/tmp/priv.hash" || rc=$?
    assert_failure "$rc" "modified file is detected by the flow"
}

test_I07_shell_initialization() {
    reset_full_state
    create_test_config

    local out rc=0
    out=$(env HOME="$TEST_HOME" ENV_DIR="$TEST_ENV_DIR" \
        zsh -c 'source "$ENV_DIR/dotfiles/.env.zsh" && type file_age_days >/dev/null && echo INIT_OK' \
        2>&1) || rc=$?
    assert_success "$rc" ".env.zsh initializes a real zsh shell"
    assert_contains "$out" "INIT_OK" "functions are defined after initialization"
}

test_I08_remote_updates_detected() {
    reset_full_state
    create_test_config
    setup_local_git_server

    source "$TEST_ENV_DIR/functions/git_funcs"

    local rc=0
    git_has_remote_updates "$TEST_ENV_DIR" || rc=$?
    assert_equals 1 "$rc" "fresh push: no remote updates"

    simulate_remote_change "remote_file.txt" "remote content"
    rc=0
    git_has_remote_updates "$TEST_ENV_DIR" || rc=$?
    assert_equals 0 "$rc" "remote commit is detected"
}

test_I09_conflict_resolution() {
    reset_full_state
    create_test_dotfile ".testrc" "repo version"
    create_home_file ".testrc" "home version"
    create_dotfiles_config

    source "$TEST_ENV_DIR/scripts/sync_dotfiles.sh"

    assert_true 'type handle_conflict &>/dev/null' "Conflict resolution should exist"
}

test_I10_cleanup_on_failure() {
    reset_full_state
    load_sync_encrypted

    mkdir -p "$TEST_ENV_DIR/tmp/test_cleanup"
    echo "temp" > "$TEST_ENV_DIR/tmp/test_cleanup/file.txt"

    TEMP_DIR="$TEST_ENV_DIR/tmp/test_cleanup"
    local rc=0
    cleanup || rc=$?

    assert_success "$rc" "cleanup runs"
    assert_dir_not_exists "$TEST_ENV_DIR/tmp/test_cleanup" "Should cleanup on failure"
}

run_all_tests() {
    start_suite "07_integration"

    run_test "I01: full setup from scratch" test_I01_full_setup_from_scratch
    run_test "I02: idempotent setup" test_I02_idempotent_setup
    run_test "I03: sync_env help" test_I03_sync_env_help
    run_test "I04: dotfiles creates links" test_I04_dotfiles_creates_links
    run_test "I05: local changes detected" test_I05_local_changes_detected
    run_test "I06: encrypted sync flow" test_I06_encrypted_sync_flow
    run_test "I07: shell initialization" test_I07_shell_initialization
    run_test "I08: remote updates detected" test_I08_remote_updates_detected
    run_test "I09: conflict resolution" test_I09_conflict_resolution
    run_test "I10: cleanup on failure" test_I10_cleanup_on_failure

    end_suite

    [[ $SUITE_FAILED -eq 0 ]]
}
