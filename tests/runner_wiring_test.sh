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
# Test: every suite name the runner can dispatch runs its script
# ----------------------------------------------------------------------------
test_runner_accepts_new_suite_names() {
    local T
    T=$(mktemp -d)
    trap 'rm -rf "$T"' RETURN

    cp "$RUNNER" "$T/run_all_tests.sh"
    cp "$SCRIPT_DIR/test_helper.sh" "$T/test_helper.sh"

    # name<TAB>file pairs for every suite the runner can dispatch
    local map
    map=$(awk '
        /if \[\[ \$run_[a-z0-9_]+ -eq 1 \]\]/ { match($0, /run_[a-z0-9_]+/); n = substr($0, RSTART+4, RLENGTH-4) }
        /run_test_suite "/ && /\$SCRIPT_DIR\// {
            line = $0; sub(/^.*\$SCRIPT_DIR\//, "", line); sub(/".*$/, "", line); print n "\t" line; n = ""
        }
    ' "$RUNNER")

    if [[ -z "$map" ]]; then
        assert_equals "non-empty" "" "runner dispatches no suites (name-to-file map is empty)"
    fi

    local name file rc content lines bad
    while IFS=$'\t' read -r name file; do
        [[ -n "$name" && -n "$file" ]] || continue

        if [[ -f "$SCRIPT_DIR/$file" ]]; then
            assert_equals "" "" "suite '$name' script tests/$file exists"
        else
            assert_equals "" "tests/$file" "suite '$name' script tests/$file must exist"
        fi

        if [[ "$file" != "test_helper.sh" ]]; then
            mkdir -p "$T/$(dirname "$file")"
            printf '#!/bin/bash\necho "%s" >> "%s/ran.txt"\n' "$file" "$T" > "$T/$file"
        fi

        : > "$T/ran.txt"
        bash "$T/run_all_tests.sh" --only "$name" --skip-docker > /dev/null 2>&1
        rc=$?

        if [[ "$name" == "docker" ]]; then
            assert_exit_code 1 "$rc" "docker suite must fail with --skip-docker (nothing ran)"
            content=$(cat "$T/ran.txt" 2>/dev/null)
            assert_equals "" "$content" "docker suite must run nothing with --skip-docker"
        else
            assert_exit_code 0 "$rc" "suite '$name' must succeed via --only"
            content=$(cat "$T/ran.txt")
            lines=$(wc -l < "$T/ran.txt")
            if [[ "$lines" -eq 1 && "$content" == "$file" ]]; then
                assert_equals "" "" "suite '$name' runs exactly tests/$file"
            else
                assert_equals "$file" "$content" "suite '$name' must run exactly tests/$file"
            fi
        fi
    done <<< "$map"

    : > "$T/ran.txt"
    bash "$T/run_all_tests.sh" setup smoke --skip-docker > /dev/null 2>&1
    rc=$?
    assert_exit_code 0 "$rc" "positional 'setup smoke' must succeed"
    content=$(cat "$T/ran.txt")
    if [[ "$content" == $'setup_test.sh\nsmoke_test.sh' || \
            "$content" == $'smoke_test.sh\nsetup_test.sh' ]]; then
        assert_equals "" "" "positional 'setup smoke' runs setup_test.sh and smoke_test.sh only"
    else
        assert_equals "" "$content" "positional 'setup smoke' must run setup_test.sh and smoke_test.sh only"
    fi

    for bad in nosuchsuite smok; do
        : > "$T/ran.txt"
        bash "$T/run_all_tests.sh" --only "$bad" > /dev/null 2>&1
        rc=$?
        assert_exit_code 1 "$rc" "--only $bad must be rejected"
        content=$(cat "$T/ran.txt" 2>/dev/null)
        assert_equals "" "$content" "--only $bad must run nothing"
    done
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
