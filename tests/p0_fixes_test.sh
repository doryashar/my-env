#!/usr/bin/env bash
# Tests for P0 bug fixes identified in docs/REVIEW_2026-06-16.md
#
# Covers:
#   #2 install_fonts.sh: ENV_DIR must resolve to repo root from real path
#   #3 setup.sh: "are we in repo?" check must succeed for real-path invocation
#   #4 setup.sh: generated crontab must not reference non-existent scripts
#   #5 sync_encrypted.sh: age-identity cleanup must run on EXIT (single trap)
#   #6 bw_funcs: add_secret/get_secret must round-trip (same item type)
#   #7 file_chat_funcs: PRIVATE_CHAT_FILE env override must work (no typo)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "P0 Bug Fix Tests"
echo "========================================"
echo ""

# ----------------------------------------------------------------------------
# Bug #2: install_fonts.sh must compute ENV_DIR pointing at the repo root
# (SCRIPT_DIR is scripts/install/ — needs to go up 2 levels, not 1)
# ----------------------------------------------------------------------------
test_install_fonts_env_dir_resolves_to_repo_root() {
    # Extract the actual path-resolution code from install_fonts.sh (lines 4-5)
    # and execute it in a subshell with BASH_SOURCE pointing at the real script
    local fonts_script="$ENV_DIR/scripts/install/install_fonts.sh"
    local computed_env_dir
    computed_env_dir=$(bash -c '
        # Replay the exact lines from install_fonts.sh
        '"$(sed -n '4,5p' "$fonts_script")"'
        echo "$ENV_DIR"
    ' "$fonts_script")
    # Bug: dirname of /home/yashar/env/scripts/install is /home/yashar/env/scripts
    # Expected: /home/yashar/env
    assert_equals "$ENV_DIR" "$computed_env_dir" \
        "install_fonts.sh ENV_DIR must resolve to repo root ($ENV_DIR)"
}

# ----------------------------------------------------------------------------
# Bug #3: setup.sh "are we in repo?" check must succeed when invoked via
# the real path scripts/install/setup.sh (the check at lines 42-43 uses only
# one ../ — needs two because the script is two levels deep)
# ----------------------------------------------------------------------------
test_setup_sh_in_repo_check_for_real_path() {
    local setup_script="$ENV_DIR/scripts/install/setup.sh"
    local script_dir
    script_dir=$(cd "$(dirname "$setup_script")" && pwd)
    # Extract the marker path from the actual `if [[ -f "$SCRIPT_DIR/..." ]]` check
    # Line 43 contains the repo.conf marker (the first key-file check)
    local marker
    marker=$(grep -m1 -oE '\$SCRIPT_DIR/[^\"]+config/repo\.conf' "$setup_script" | sed 's|\$SCRIPT_DIR/||')
    [[ -z "$marker" ]] && { skip_test "Could not extract repo.conf marker from setup.sh"; return; }
    local resolved="$script_dir/$marker"
    # Normalize (resolve ../..)
    local normalized
    normalized=$(cd "$(dirname "$resolved")" 2>/dev/null && pwd)/$(basename "$resolved")
    assert_file_exists "$normalized" \
        "setup.sh in-repo marker (\$SCRIPT_DIR/$marker) must resolve to existing file for real-path invocation"
}

# ----------------------------------------------------------------------------
# Bug #4: generated crontab (setup.sh:883-889) must not reference scripts
# that don't exist
# ----------------------------------------------------------------------------
test_generated_crontab_references_existing_scripts() {
    # Extract the actual heredoc that setup.sh writes when config/crontab is absent.
    # Located between `cat > "$cron_file" << 'EOF'` and the closing `EOF`.
    local setup_script="$ENV_DIR/scripts/install/setup.sh"
    local generated
    generated=$(awk "/cat > \"\\\$cron_file\" << 'EOF'/,/^EOF$/" "$setup_script" \
        | sed -e '1d' -e '$d')

    [[ -z "$generated" ]] && { skip_test "Could not extract crontab heredoc from setup.sh"; return; }

    # Expand $HOME and verify every script referenced actually exists
    local missing=0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        local path
        path=$(echo "$line" | grep -oE '\$HOME/env/scripts/[^ >]+' | head -1)
        [[ -z "$path" ]] && continue
        local expanded="${path/\$HOME/$HOME}"
        if [[ ! -e "$expanded" ]]; then
            echo "  MISSING: $expanded (from: $line)"
            missing=$((missing + 1))
        fi
    done <<< "$generated"

    assert_equals 0 "$missing" \
        "Generated crontab must reference only scripts that exist (missing: $missing)"
}

# ----------------------------------------------------------------------------
# Bug #5: sync_encrypted.sh must run age-identity cleanup on EXIT.
# Bash only allows ONE trap per signal; setting a second trap replaces the
# first. Verify the script chains both cleanups (or that only one trap
# statement exists, calling both cleanups).
# ----------------------------------------------------------------------------
test_sync_encrypted_has_single_chained_exit_trap() {
    local script="$ENV_DIR/scripts/sync/sync_encrypted.sh"
    # Count actual `trap ... EXIT` statements (not comments) — should be exactly 1
    local trap_count
    trap_count=$(grep -E '^[[:space:]]*trap .* EXIT' "$script" | grep -vc '^[[:space:]]*#')
    assert_equals 1 "$trap_count" \
        "sync_encrypted.sh must have exactly one EXIT trap (found $trap_count — bash only keeps the last)"
    # And the cleanup() function must invoke _cleanup_age_identity (directly or chained)
    local cleanup_calls_age
    if grep -A 20 '^cleanup()' "$script" | grep -q '_cleanup_age_identity'; then
        cleanup_calls_age=1
    else
        cleanup_calls_age=0
    fi
    assert_equals 1 "$cleanup_calls_age" \
        "cleanup() (the EXIT trap handler) must invoke _cleanup_age_identity so the age identity file is wiped"
}

# ----------------------------------------------------------------------------
# Bug #6: bw_funcs add_secret / get_secret must round-trip.
# add_secret creates type:2 secure note with secret in .notes.
# get_secret reads .login.password — always null for secure notes.
# Use a mocked `bw` and `jq` to verify the contract without touching real BW.
# ----------------------------------------------------------------------------
test_bw_funcs_add_get_roundtrip() {
    # Mock bw to capture the JSON add_secret produces, and replay it for get_secret
    local tmp_capture
    tmp_capture=$(mktemp)
    assert_file_exists "$tmp_capture" "mktemp should succeed"

    bw() {
        case "${1:-} ${2:-}" in
            "encode -") cat | base64 -w0 ;;
            "encode ")  cat | base64 -w0 ;;
            "encode")   cat | base64 -w0 ;;
            "create item")
                local b64
                b64=$(cat)
                echo "$b64" | base64 -d > "$tmp_capture"
                echo "mock-item-id"
                ;;
            "get item") cat "$tmp_capture" ;;
            *) return 1 ;;
        esac
    }
    # Export the function so subshells (command substitution) see it
    export -f bw
    export TMP_CAPTURE="$tmp_capture"

    # Source bw_funcs (defines add_secret, get_secret).
    # bw_funcs expects logging colors (GREEN) from common_funcs.
    # shellcheck disable=SC1091
    source "$ENV_DIR/functions/common_funcs"
    # shellcheck disable=SC1091
    source "$ENV_DIR/functions/bw_funcs"

    local test_name="test-secret-$(date +%s)-$RANDOM"
    local test_value="super-secret-value-$$"

    add_secret "$test_name" "$test_value" >/dev/null 2>&1
    local retrieved
    retrieved=$(get_secret "$test_name" 2>/dev/null)

    assert_equals "$test_value" "$retrieved" \
        "get_secret(add_secret(name, value)) must return value (round-trip)"

    rm -f "$tmp_capture"
}

# ----------------------------------------------------------------------------
# Bug #7: file_chat_funcs PRIVATE_CHAT_FILE env-var override must work.
# Currently broken by typo: ${CHPRIVATE_CHAT_FILEAT_FILE:-...}
# ----------------------------------------------------------------------------
test_file_chat_private_override() {
    local custom="/tmp/test-private-chatfile-$$"
    rm -f "$custom"
    # Source the file with the override set
    PRIVATE_CHAT_FILE="$custom" bash -c '
        source "'"$ENV_DIR"'/functions/file_chat_funcs" 2>/dev/null
        echo "$PRIVATE_CHAT_FILE"
    '
    local result
    result=$(PRIVATE_CHAT_FILE="$custom" bash -c '
        # file_chat_funcs uses setopt (zsh-only) — guard against failure
        source "'"$ENV_DIR"'/functions/file_chat_funcs" 2>/dev/null
        echo "$PRIVATE_CHAT_FILE"
    ')
    assert_equals "$custom" "$result" \
        "PRIVATE_CHAT_FILE override must be respected (got: $result)"
}

# ----------------------------------------------------------------------------
# Run all tests
# ----------------------------------------------------------------------------
test_install_fonts_env_dir_resolves_to_repo_root
test_setup_sh_in_repo_check_for_real_path
test_generated_crontab_references_existing_scripts
test_sync_encrypted_has_single_chained_exit_trap
test_bw_funcs_add_get_roundtrip
test_file_chat_private_override

print_test_summary
