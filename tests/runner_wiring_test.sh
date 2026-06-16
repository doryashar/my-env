#!/usr/bin/env bash
# Tests for run_all_tests.sh wiring of orphan test suites + stale-path fixes.
#
# Covers:
#   - run_all_tests.sh --help lists previously-orphan suites
#   - The 3 stale-path tests now reference scripts/tools/ correctly
#   - Invoking each new suite name actually runs the corresponding script

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "Test Runner Wiring + Stale-Path Tests"
echo "========================================"
echo ""

RUNNER="$SCRIPT_DIR/run_all_tests.sh"

# ----------------------------------------------------------------------------
# Test: previously-orphan suites must be listed in --help output
# ----------------------------------------------------------------------------
test_runner_help_lists_orphan_suites() {
    local help_output
    help_output=$("$RUNNER" --help 2>&1)

    local missing=""
    for suite in sync_dotfiles tmux_config oref_alert_monitor zerotier p0_fixes security_fixes; do
        if ! echo "$help_output" | grep -qw "$suite"; then
            missing="$missing $suite"
        fi
    done

    if [[ -z "$missing" ]]; then
        assert_equals "" "" \
            "run_all_tests.sh --help must list previously-orphan suites"
    else
        assert_equals "" "$missing" \
            "run_all_tests.sh --help must list previously-orphan suites (missing:$missing)"
    fi
}

# ----------------------------------------------------------------------------
# Test: invoking each new suite name is accepted (not 'Unknown option')
# ----------------------------------------------------------------------------
test_runner_accepts_new_suite_names() {
    local bad=""
    for suite in sync_dotfiles tmux_config oref_alert_monitor zerotier p0_fixes security_fixes; do
        # --only <suite> should be accepted (exit 0 from --help path is fine;
        # we only check it's not rejected as unknown)
        out=$("$RUNNER" --only "$suite" --help 2>&1 || true)
        if echo "$out" | grep -q "Unknown option: --only"; then
            bad="$bad $suite"
        fi
    done
    if [[ -z "$bad" ]]; then
        assert_equals "" "" \
            "run_all_tests.sh must accept new --only SUITE names"
    else
        assert_equals "" "$bad" \
            "run_all_tests.sh must accept new --only SUITE names (rejected:$bad)"
    fi
}

# ----------------------------------------------------------------------------
# Stale-path fix: test_github_token.sh references scripts/tools/new_claude.sh
# ----------------------------------------------------------------------------
test_github_token_uses_tools_path() {
    local f="$SCRIPT_DIR/test_github_token.sh"
    # Bug: the test invokes new_claude.sh from scripts/ (cd scripts && ./new_claude.sh),
    # but the script now lives at scripts/tools/new_claude.sh. The test must cd into
    # scripts/tools/ or reference the full tools/new_claude.sh path.
    if grep -q 'tools/new_claude.sh\|scripts/tools' "$f"; then
        assert_equals "tools/" "tools/" \
            "test_github_token.sh must reference scripts/tools/ path"
    else
        assert_equals "tools/" "scripts/ (no tools/)" \
            "test_github_token.sh must reference scripts/tools/ path"
    fi
}

# ----------------------------------------------------------------------------
# Stale-path fix: test_git_remotes_fixed.sh references scripts/tools/new_claude.sh
# ----------------------------------------------------------------------------
test_git_remotes_fixed_uses_tools_path() {
    local f="$SCRIPT_DIR/test_git_remotes_fixed.sh"
    # The bug: $HOME/env/scripts/new_claude.sh (no tools/)
    if grep -qE 'env/scripts/new_claude\.sh' "$f" && \
       ! grep -q 'env/scripts/tools/new_claude.sh' "$f"; then
        assert_equals "tools/new_claude.sh" "scripts/new_claude.sh (no tools/)" \
            "test_git_remotes_fixed.sh must reference scripts/tools/new_claude.sh"
    else
        assert_equals "tools/new_claude.sh" "tools/new_claude.sh" \
            "test_git_remotes_fixed.sh must reference scripts/tools/new_claude.sh"
    fi
}

# ----------------------------------------------------------------------------
# Stale-path fix: test_oref_alert_monitor.sh references scripts/tools/oref_alert_monitor.sh
# ----------------------------------------------------------------------------
test_oref_monitor_uses_tools_path() {
    local f="$SCRIPT_DIR/test_oref_alert_monitor.sh"
    # The bug: MONITOR_SCRIPT points at scripts/oref_alert_monitor.sh (no tools/)
    if grep -qE 'scripts/oref_alert_monitor\.sh' "$f" && \
       ! grep -q 'scripts/tools/oref_alert_monitor.sh' "$f"; then
        assert_equals "tools/oref_alert_monitor.sh" "scripts/oref_alert_monitor.sh (no tools/)" \
            "test_oref_alert_monitor.sh must reference scripts/tools/oref_alert_monitor.sh"
    else
        assert_equals "tools/oref_alert_monitor.sh" "tools/oref_alert_monitor.sh" \
            "test_oref_alert_monitor.sh must reference scripts/tools/oref_alert_monitor.sh"
    fi
}

# ----------------------------------------------------------------------------
# Run all tests
# ----------------------------------------------------------------------------
test_runner_help_lists_orphan_suites
test_runner_accepts_new_suite_names
test_github_token_uses_tools_path
test_git_remotes_fixed_uses_tools_path
test_oref_monitor_uses_tools_path

print_test_summary
