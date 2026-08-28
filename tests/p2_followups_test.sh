#!/usr/bin/env bash
# Tests for P2 follow-ups from docs/code_review_2026-08-28.md
#
# Covers:
#   F1 update_infrastructure.sh: every git invocation must be scoped to
#      $ENV_DIR via -C (running in CWD fetches/overwrites the wrong repo)
#   F2 ENV_DIR clobber: sync_env.sh / sync_encrypted.sh /
#      update_infrastructure.sh / setup.sh source config/repo.conf which
#      re-sets ENV_DIR to the hardcoded ~/env, silently retargeting
#      installs cloned elsewhere
#   F3 common_funcs check_github_repo_exists: read-only check must not
#      rm/replace ~/.ssh (symlink) or append to ~/.ssh/known_hosts
#   F4 logging.sh debug redaction must include TELEGRAM_BOT_TOKEN

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

WORK_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# ----------------------------------------------------------------------------
# F1: all git calls in update_infrastructure.sh scoped with -C "$ENV_DIR"
# ----------------------------------------------------------------------------
test_update_infra_git_scoped_to_env_dir() {
    local script="$ENV_DIR/scripts/sync/update_infrastructure.sh"
    local total scoped
    total=$(grep -E '(^|[[:space:](;!&|])git ' "$script" \
        | grep -v '^[[:space:]]*#' | wc -l)
    scoped=$(grep -E '(^|[[:space:](;!&|])git -C "\$ENV_DIR" ' "$script" \
        | grep -v '^[[:space:]]*#' | wc -l)
    assert_equals "$total" "$scoped" \
        "every git call in update_infrastructure.sh must use -C \"\$ENV_DIR\" ($scoped/$total scoped)"
}

# ----------------------------------------------------------------------------
# F2 helper: extract a script's top-level ENV_DIR/repo.conf block, replay
# it from a sandbox copy (so BASH_SOURCE resolves inside the sandbox) with
# a repo.conf that tries to clobber ENV_DIR, and report the final ENV_DIR.
# ----------------------------------------------------------------------------
replay_env_dir_block() {
    local script="$1"       # real script path
    local from="$2"         # sed range start regex
    local to="$3"           # sed range end regex (inclusive)
    local tail_lines="${4:-0}"  # extra lines after $to to include

    local sb="$WORK_DIR/sb_$(basename "$script" .sh)"
    rm -rf "$sb"
    mkdir -p "$sb/env/scripts/sync" "$sb/env/config" "$sb/env/functions"

    cp "$ENV_DIR/functions/common_funcs" "$sb/env/functions/"
    cp "$ENV_DIR/functions/logging.sh" "$sb/env/functions/"

    # repo.conf deliberately points ENV_DIR somewhere wrong
    cat > "$sb/env/config/repo.conf" <<'CONF'
ENV_DIR="/clobbered/by/repo/conf"
UPSTREAM_URL="git@example.com:upstream/repo.git"
PRIVATE_URL="git@example.com:private/repo.git"
CONF

    local dst="$sb/env/scripts/sync/$(basename "$script")"
    # NB: '|' delimiter — the range patterns contain '/' characters
    sed -n "\|$from|,\|$to|p" "$script" > "$dst"
    [[ "$tail_lines" -gt 0 ]] && \
        sed -n "\|$to|,+${tail_lines}p" "$script" | tail -n "+2" >> "$dst"
    echo 'echo "$ENV_DIR"' >> "$dst"

    # Sandbox HOME: the extracted top of sync_encrypted.sh runs
    # ssh-keyscan against ~/.ssh/known_hosts
    HOME="$sb" bash "$dst" 2>/dev/null
}

test_sync_env_preserves_derived_env_dir() {
    local result
    result=$(replay_env_dir_block "$ENV_DIR/scripts/sync/sync_env.sh" \
        '^SCRIPT_DIR=' '^source "\$REPO_CONFIG_FILE"' 3)
    assert_equals "$WORK_DIR/sb_sync_env/env" "$result" \
        "sync_env.sh: sourced repo.conf must not clobber derived ENV_DIR"
}

test_sync_encrypted_preserves_derived_env_dir() {
    local result
    result=$(replay_env_dir_block "$ENV_DIR/scripts/sync/sync_encrypted.sh" \
        '^SCRIPT_DIR=' 'source "\$ENV_DIR/config/repo.conf"' 3)
    assert_equals "$WORK_DIR/sb_sync_encrypted/env" "$result" \
        "sync_encrypted.sh: sourced repo.conf must not clobber derived ENV_DIR"
}

test_update_infra_preserves_derived_env_dir() {
    local result
    result=$(replay_env_dir_block "$ENV_DIR/scripts/sync/update_infrastructure.sh" \
        '^SCRIPT_DIR=' 'source "\$ENV_DIR/config/repo.conf"' 3)
    assert_equals "$WORK_DIR/sb_update_infrastructure/env" "$result" \
        "update_infrastructure.sh: sourced repo.conf must not clobber derived ENV_DIR"
}

test_setup_preserves_env_dir_when_reading_repo_conf() {
    # Extract sync_encrypted_files' repo.conf block from setup.sh and
    # replay it with ENV_DIR pointing at a sandbox repo.conf fixture.
    local sb="$WORK_DIR/sb_setup"
    rm -rf "$sb"
    mkdir -p "$sb/env/config"
    cat > "$sb/env/config/repo.conf" <<'CONF'
ENV_DIR="/clobbered/by/repo/conf"
PRIVATE_URL="git@example.com:private/repo.git"
CONF

    local block="$WORK_DIR/setup_block.sh"
    sed -n '/local private_url=""/,/^    fi$/p' \
        "$ENV_DIR/scripts/install/setup.sh" > "$block"

    if ! grep -q "repo.conf" "$block"; then
        echo -e "${RED}✗${NC} could not extract setup.sh repo.conf block"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TESTS_RUN=$((TESTS_RUN + 1))
        return
    fi

    local out
    out=$(bash -c '
        ENV_DIR="'"$sb"'/env"
        info() { :; }
        warning() { :; }
        source "'"$block"'"
        echo "$ENV_DIR|$private_url"
    ' 2>/dev/null)
    assert_equals "$sb/env|git@example.com:private/repo.git" "$out" \
        "setup.sh: reading PRIVATE_URL must not clobber ENV_DIR"
}

# ----------------------------------------------------------------------------
# F3: check_github_repo_exists must not touch ~/.ssh
# ----------------------------------------------------------------------------
test_check_github_repo_exists_preserves_ssh_symlink() {
    local home="$WORK_DIR/fakehome"
    local sshdir="$WORK_DIR/sshdir"
    mkdir -p "$sshdir" "$home"
    ln -s "$sshdir" "$home/.ssh"
    touch "$sshdir/known_hosts"

    # gh shim: present but not authenticated -> falls through to ls-remote
    local shim="$WORK_DIR/shims"
    mkdir -p "$shim"
    printf '#!/bin/bash\nexit 1\n' > "$shim/gh"
    chmod +x "$shim/gh"

    local out rc=0
    out=$(HOME="$home" PATH="$shim:$PATH" bash -c '
        source "$1/functions/common_funcs"
        get_github_token() { echo ""; }
        check_github_repo_exists "git@github.com:some/repo.git"
        echo "CHECK_DONE"
    ' _ "$ENV_DIR" 2>&1) || rc=$?

    if [[ -L "$home/.ssh" ]]; then
        echo -e "${GREEN}✓${NC} ~/.ssh symlink must survive check_github_repo_exists"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} ~/.ssh symlink must survive check_github_repo_exists"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    assert_contains "$out" "CHECK_DONE" "check must complete (not abort)"
}

test_check_github_repo_exists_leaves_known_hosts_untouched() {
    local home="$WORK_DIR/fakehome2"
    mkdir -p "$home/.ssh"
    printf 'existing-host-line\n' > "$home/.ssh/known_hosts"

    local shim="$WORK_DIR/shims2"
    mkdir -p "$shim"
    printf '#!/bin/bash\nexit 1\n' > "$shim/gh"
    chmod +x "$shim/gh"

    HOME="$home" PATH="$shim:$PATH" bash -c '
        source "$1/functions/common_funcs"
        get_github_token() { echo ""; }
        check_github_repo_exists "git@github.com:some/repo.git"
    ' _ "$ENV_DIR" >/dev/null 2>&1 || true

    assert_equals "existing-host-line" \
        "$(cat "$home/.ssh/known_hosts" 2>/dev/null)" \
        "known_hosts must not gain keyscan entries from a read-only check"
}

# ----------------------------------------------------------------------------
# F4: debug redaction must cover TELEGRAM_BOT_TOKEN
# ----------------------------------------------------------------------------
test_debug_redacts_telegram_token() {
    local out
    out=$(ENV_DEBUG=1 bash -c '
        source "$1/functions/logging.sh"
        debug "TELEGRAM_BOT_TOKEN=123456:ABC-DEF call failed"
    ' _ "$ENV_DIR" 2>/dev/null)
    if [[ "$out" == *123456:ABC-DEF* ]]; then
        echo -e "${RED}✗${NC} debug must redact TELEGRAM_BOT_TOKEN values"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo -e "${GREEN}✓${NC} debug must redact TELEGRAM_BOT_TOKEN values"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
    echo "========================================"
    echo "P2 Follow-up Tests"
    echo "========================================"
    echo ""

    test_update_infra_git_scoped_to_env_dir
    test_sync_env_preserves_derived_env_dir
    test_sync_encrypted_preserves_derived_env_dir
    test_update_infra_preserves_derived_env_dir
    test_setup_preserves_env_dir_when_reading_repo_conf
    test_check_github_repo_exists_preserves_ssh_symlink
    test_check_github_repo_exists_leaves_known_hosts_untouched
    test_debug_redacts_telegram_token

    echo ""
    print_test_summary
}

main "$@"
