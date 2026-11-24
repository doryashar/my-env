#!/bin/bash
#
# Sync Dotfiles Conflict-Handling Tests
#
# Behavioural tests for the conflict handling in sync_dotfiles.sh
# (handle_conflict, backward_sync_file) and for remove_all_broken_links.
#
# Each scenario runs in its own child process, so the script's
# set -euo pipefail applies for real and one abort cannot stop the others.
# When this file is started with `--scenario NAME` it acts as that child:
#   set -euo pipefail; source the real script; scenario_NAME; exit $?
# (sourcing only defines the functions because of the script's main guard).
# Otherwise it creates a temp dir T (removed on EXIT) and runs the
# scenarios as child processes, capturing stdout+stderr and the exit code.
#
# prompt is redefined in the child from the ANSWER environment variable.
# ANSWER is a space-separated queue of menu answers, consumed one per
# prompt() call: a recursive menu (choice 3 "Show diff") therefore
# receives a different next answer and the child terminates. With a
# single answer the behaviour is identical to a fixed ANSWER.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/test_sync_dotfiles_conflicts.sh"

source "$SCRIPT_DIR/test_helper.sh"

# ---- scenario functions (executed inside the child) -------------------------

# S1: menu choice 3 (show diff) must not abort; the menu asks again.
scenario_S1() {
    echo a > "$T/s"
    echo b > "$T/t"
    handle_conflict "$T/s" "$T/t" ask
    echo AFTER_OK
}

# S2: strategy local replaces a directory's content atomically.
scenario_S2() {
    mkdir -p "$T/repo/cfg" "$T/home/cfg"
    echo r > "$T/repo/cfg/repo"
    echo l > "$T/home/cfg/local"
    handle_conflict "$T/repo/cfg" "$T/home/cfg" local
    echo AFTER_OK
}

# S3: menu choice 1 (keep local) does the same.
scenario_S3() {
    mkdir -p "$T/repo/cfg" "$T/home/cfg"
    echo r > "$T/repo/cfg/repo"
    echo l > "$T/home/cfg/local"
    handle_conflict "$T/repo/cfg" "$T/home/cfg" ask
    echo AFTER_OK
}

# S4: backward_sync_file replaces a repo directory when the target is newer.
scenario_S4() {
    mkdir -p "$T/repo/d" "$T/home/d"
    echo o > "$T/repo/d/old"
    echo n > "$T/home/d/new"
    touch "$T/home/d/new"
    # Pin the repo directory to an old mtime so "target is newer" is
    # deterministic (directory mtimes are second-resolution).
    touch -t 200001010000 "$T/repo/d"
    backward_sync_file d "$T/home/d" "link=soft conflict=ask"
    echo AFTER_OK
}

# S5: only dangling links managed by the repo are removed.
scenario_S5() {
    ln -s "$T/repo/missing" "$T/home/into-repo"
    ln -s /nonexistent/xyz "$T/home/elsewhere"
    touch "$T/home/real"
    remove_all_broken_links "$T/home"
    echo AFTER_OK
}

# S6: no terminal available; the conflict must not kill the script.
scenario_S6() {
    echo a > "$T/s"
    echo b > "$T/t"
    handle_conflict "$T/s" "$T/t" ask
    echo AFTER_OK
}

# S7: with a terminal the menu works; choice 2 uses the repo version.
scenario_S7() {
    echo a > "$T/s"
    echo b > "$T/t"
    handle_conflict "$T/s" "$T/t" ask
    echo AFTER_OK
}

# ---- child mode -------------------------------------------------------------
if [[ "${1:-}" == "--scenario" ]]; then
    SCENARIO_NAME="$2"
    set -euo pipefail
    source "$SCRIPT_DIR/../scripts/sync/sync_dotfiles.sh"

    # Consume the next answer from the space-separated ANSWER queue.
    prompt() {
        local _next="${ANSWER%% *}"
        if [[ "$ANSWER" == *" "* ]]; then
            ANSWER="${ANSWER#* }"
        else
            ANSWER=""
        fi
        printf -v "$2" '%s' "$_next"
    }

    "scenario_$SCENARIO_NAME"
    exit $?
fi
# ---- parent mode -------------------------------------------------------------

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Shared fixtures: an isolated HOME and a minimal repo whose only content
# is a fixture common_funcs providing just the logging helpers that
# sync_dotfiles.sh uses (the real library is a test double here so the
# scenarios are hermetic and deterministic).
mkdir -p "$T/home" "$T/repo/functions"
cat > "$T/repo/functions/common_funcs" <<'EOF'
# Minimal fixture library for test_sync_dotfiles_conflicts.sh:
# only the logging helpers sync_dotfiles.sh uses.
NC=''
RED=''
GREEN=''
YELLOW=''
BLUE=''
PURPLE=''
title() { printf '%s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
warning() { printf '[WARNING] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
log_debug() { :; }
prompt() { printf -v "$2" '%s' "${ANSWER:-}"; }
EOF

# LAST_OUT / LAST_RC hold the captured output and exit code of the most
# recent child run.

# Plain child process (no terminal guarantees).
run_child() {
    local name="$1" answer="${2-}"
    LAST_OUT=$(ANSWER="$answer" HOME="$T/home" ENV_DIR="$T/repo" T="$T" \
        bash "$SCRIPT_PATH" --scenario "$name" 2>&1)
    LAST_RC=$?
}

# Child process with a terminal substitute (pty via script(1)), so
# can_ask succeeds deterministically no matter how the parent was started.
run_terminal_child() {
    local name="$1" answer="${2-}"
    LAST_OUT=$(ANSWER="$answer" HOME="$T/home" ENV_DIR="$T/repo" T="$T" \
        script -qec "bash '$SCRIPT_PATH' --scenario $name" /dev/null 2>&1)
    LAST_RC=$?
}

# Child process detached from any terminal (new session, stdin /dev/null).
run_noterminal_child() {
    local name="$1" answer="${2-}"
    LAST_OUT=$(ANSWER="$answer" HOME="$T/home" ENV_DIR="$T/repo" T="$T" \
        setsid -w bash "$SCRIPT_PATH" --scenario "$name" </dev/null 2>&1)
    LAST_RC=$?
}

# ---- parent: one test per scenario -------------------------------------------

test_s1_choice3_does_not_abort() {
    run_terminal_child S1 "3 5"
    assert_exit_code 0 "$LAST_RC" "S1: choice 3 must not abort (exit 0)"
    assert_contains "$LAST_OUT" "+a" "S1: output shows the diff (+a)"
    assert_contains "$LAST_OUT" "-b" "S1: output shows the diff (-b)"
    assert_contains "$LAST_OUT" "AFTER_OK" "S1: menu returns and scenario completes"
    assert_equals "a" "$(cat "$T/s")" "S1: source file unchanged"
    assert_equals "b" "$(cat "$T/t")" "S1: target file unchanged"
}

test_s2_strategy_local_replaces_directory() {
    run_child S2
    assert_exit_code 0 "$LAST_RC" "S2: strategy local exits 0"
    assert_contains "$LAST_OUT" "AFTER_OK" "S2: scenario completes"
    assert_equals "local" "$(ls -A "$T/repo/cfg")" \
        "S2: repo dir contains exactly one entry (local)"
    assert_equals "l" "$(cat "$T/repo/cfg/local")" "S2: local content copied"
    local leftovers
    leftovers=$(find "$T/repo" -name '.cfg.copying.*' | wc -l)
    assert_equals 0 "$leftovers" "S2: no .cfg.copying.* staging leftovers"
}

test_s3_choice1_does_the_same() {
    run_terminal_child S3 "1"
    assert_exit_code 0 "$LAST_RC" "S3: choice 1 exits 0"
    assert_contains "$LAST_OUT" "AFTER_OK" "S3: scenario completes"
    assert_equals "local" "$(ls -A "$T/repo/cfg")" \
        "S3: repo dir contains exactly one entry (local)"
    assert_equals "l" "$(cat "$T/repo/cfg/local")" "S3: local content copied"
    local leftovers
    leftovers=$(find "$T/repo" -name '.cfg.copying.*' | wc -l)
    assert_equals 0 "$leftovers" "S3: no .cfg.copying.* staging leftovers"
}

test_s4_backward_sync_replaces_directory() {
    run_child S4
    assert_exit_code 0 "$LAST_RC" "S4: backward_sync_file exits 0"
    assert_contains "$LAST_OUT" "AFTER_OK" "S4: scenario completes"
    assert_equals "new" "$(ls -A "$T/repo/d")" \
        "S4: repo dir contains exactly new"
    assert_equals "n" "$(cat "$T/repo/d/new")" "S4: target content copied"
}

test_s5_only_managed_dangling_links_removed() {
    run_child S5
    assert_exit_code 0 "$LAST_RC" "S5: remove_all_broken_links exits 0"
    assert_contains "$LAST_OUT" "AFTER_OK" "S5: scenario completes"
    assert_file_not_exists "$T/home/into-repo" \
        "S5: managed dangling link removed"
    assert_symlink_exists "$T/home/elsewhere" \
        "S5: unmanaged dangling link kept"
    assert_file_exists "$T/home/real" "S5: regular file kept"
}

test_s6_no_terminal_does_not_kill_script() {
    run_noterminal_child S6
    assert_exit_code 0 "$LAST_RC" "S6: no-terminal conflict exits 0"
    assert_contains "$LAST_OUT" "no terminal" "S6: warns about the missing terminal"
    assert_contains "$LAST_OUT" "AFTER_OK" "S6: scenario completes after the conflict"
    assert_equals "a" "$(cat "$T/s")" "S6: source file unchanged"
    assert_equals "b" "$(cat "$T/t")" "S6: target file unchanged"
}
test_s7_terminal_substitute_menu_works() {
    run_terminal_child S7 "2"
    assert_exit_code 0 "$LAST_RC" "S7: choice 2 exits 0"
    assert_contains "$LAST_OUT" "AFTER_OK" "S7: scenario completes"
    assert_symlink_exists "$T/t" "S7: target is now a symlink"
    assert_equals "$T/s" "$(readlink "$T/t")" "S7: symlink points at the source"
}

test_s1_choice3_does_not_abort
test_s2_strategy_local_replaces_directory
test_s3_choice1_does_the_same
test_s4_backward_sync_replaces_directory
test_s5_only_managed_dangling_links_removed
test_s6_no_terminal_does_not_kill_script
test_s7_terminal_substitute_menu_works

print_test_summary
exit $?
