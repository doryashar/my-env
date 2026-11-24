#!/usr/bin/env bash
# Behavioural tests for scripts/storagebox/bisync-run.sh (temp dirs, no network).
#
# Covers:
#   - mount failure exits 7 before any pair runs
#   - first run initialises unregistered pairs with --resync, skips system dirs
#   - registered pairs then run regular (no silent auto-resync)
#   - real bisync semantics: local changes propagate to the remote side
#   - a new top-level directory is initialised exactly once
#   - --only-pair runs a single pair; unknown pair names exit 2
#   - lost listings are reported (non-zero exit), never auto-fixed
#   - an explicit --resync re-baselines every pair
#   - log rotation above BISYNC_LOG_MAX_BYTES

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

# test_helper.sh has no assert_not_contains
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $message"
        echo "  Found:  $needle"
        echo "  In:     $haystack"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

echo "========================================"
echo "StorageBox Bisync Runner Tests"
echo "========================================"
echo ""

RUNNER="${BISYNC_RUNNER:-$SCRIPT_DIR/../scripts/storagebox/bisync-run.sh}"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/local/alpha" "$T/local/System Volume Information" \
    "$T/remote/alpha" "$T/wd" "$T/logs" "$T/bin"
echo "r" > "$T/local/rootfile"
echo "one" > "$T/local/alpha/file1"
echo "a2" > "$T/local/alpha/file2"
echo "a3" > "$T/local/alpha/file3"
echo "a4" > "$T/local/alpha/file4"
echo "a5" > "$T/local/alpha/file5"
echo "sysinfo" > "$T/local/System Volume Information/junk"
printf '#!/bin/bash\nexit "${MOUNT_RC:-0}"\n' > "$T/bin/mount-check.sh"
chmod +x "$T/bin/mount-check.sh"
touch "$T/empty.conf"

export BISYNC_LOCAL="$T/local"
export BISYNC_REMOTE="$T/remote"
export BISYNC_WORKDIR="$T/wd"
export BISYNC_LOG="$T/logs/bisync.log"
export BISYNC_LOCK="$T/logs/lock"
export BISYNC_MOUNT_CHECK="$T/bin/mount-check.sh"
export RCLONE_CONFIG="$T/empty.conf"

log_lines=0

run_runner() {
    # runs the runner, sends its output to $T/logs/run.out, returns its exit code
    if [ -f "$BISYNC_LOG" ]; then
        log_lines=$(wc -l < "$BISYNC_LOG")
    else
        log_lines=0
    fi
    bash "$RUNNER" "$@" > "$T/logs/run.out" 2>&1
}

newlog() {
    # only the log lines written since the previous run
    tail -n +"$((log_lines + 1))" "$BISYNC_LOG" 2>/dev/null
}

log_content() {
    cat "$BISYNC_LOG" 2>/dev/null
}

# S1: mount failure -> exit 7, nothing runs
MOUNT_RC=1 run_runner
assert_exit_code 7 $? "S1: mount failure must exit 7"
assert_not_contains "$(log_content)" "pass start" \
    "S1: log must not contain 'pass start' after a mount failure"

# S2: first run initialises every pair with --resync
run_runner
assert_exit_code 0 $? "S2: first run must succeed"
s2=$(newlog)
assert_contains "$s2" "pair[alpha] start --resync" \
    "S2: unregistered pair alpha starts with --resync"
assert_contains "$s2" "pair[System Volume Information] skipped" \
    "S2: system directory is skipped"
assert_contains "$s2" "pair[.] start --resync" \
    "S2: root pair starts with --resync"
assert_contains "$s2" "pass exit=0 failed=" \
    "S2: pass exit line shows no failed pairs"
assert_file_exists "$T/remote/alpha/file1" "S2: file1 synced to remote"
assert_file_exists "$T/remote/rootfile" "S2: rootfile synced to remote"
assert_file_not_exists "$T/remote/System Volume Information" \
    "S2: system directory never synced"
registry="$(cat "$BISYNC_WORKDIR/storagebox-pairs.txt" 2>/dev/null)"
if grep -qxF -- "alpha" "$BISYNC_WORKDIR/storagebox-pairs.txt" 2>/dev/null && \
   grep -qxF -- "." "$BISYNC_WORKDIR/storagebox-pairs.txt" 2>/dev/null; then
    assert_equals "" "" "S2: registry contains the lines 'alpha' and '.'"
else
    assert_equals "" "registry: $registry" \
        "S2: registry must contain the lines 'alpha' and '.'"
fi

# S3: second run - registered pairs run regular
run_runner
assert_exit_code 0 $? "S3: second run must succeed"
s3=$(newlog)
assert_contains "$s3" "pair[alpha] start regular" \
    "S3: registered pair alpha runs regular"
assert_contains "$s3" "pair[.] start regular" \
    "S3: registered root pair runs regular"

# S4: real bisync semantics - local changes propagate
rm "$T/local/alpha/file1"
echo "six" > "$T/local/alpha/file6"
run_runner
assert_exit_code 0 $? "S4: sync after local changes must succeed"
assert_file_not_exists "$T/remote/alpha/file1" \
    "S4: local deletion propagated to remote"
assert_file_exists "$T/remote/alpha/file6" \
    "S4: new local file synced to remote"
assert_file_exists "$T/remote/alpha/file2" \
    "S4: untouched file remains on remote"

# S5: a new top-level directory is initialised exactly once
mkdir -p "$T/local/beta"
echo "x1" > "$T/local/beta/x1"
echo "x2" > "$T/local/beta/x2"
echo "x3" > "$T/local/beta/x3"
echo "x4" > "$T/local/beta/x4"
echo "x5" > "$T/local/beta/x5"
run_runner
assert_exit_code 0 $? "S5: run with a new directory must succeed"
s5=$(newlog)
assert_contains "$s5" "pair[beta] start --resync" \
    "S5: new pair beta initialised with --resync"
assert_contains "$s5" "pair[alpha] start regular" \
    "S5: existing pair alpha stays regular"
assert_file_exists "$T/remote/beta/x1" "S5: beta content synced"
assert_contains "$(cat "$BISYNC_WORKDIR/storagebox-pairs.txt")" "beta" \
    "S5: registry contains beta"
run_runner
assert_exit_code 0 $? "S5: repeat run must succeed"
assert_contains "$(newlog)" "pair[beta] start regular" \
    "S5: second run of beta is regular"

# S6: --only-pair runs a single pair
rm "$T/local/beta/x1"
run_runner --only-pair beta
assert_exit_code 0 $? "S6: --only-pair beta must succeed"
s6=$(newlog)
assert_contains "$s6" "pair[beta] start regular" \
    "S6: the beta pair ran"
assert_not_contains "$s6" "pair[alpha]" \
    "S6: the alpha pair must not run"
assert_not_contains "$s6" "pair[.]" \
    "S6: the root pair must not run"
assert_file_not_exists "$T/remote/beta/x1" \
    "S6: deletion propagated with --only-pair"
assert_file_exists "$T/remote/beta/x2" \
    "S6: untouched beta file remains on remote"

# S7: unknown pair name -> exit 2
run_runner --only-pair nosuchdir
assert_exit_code 2 $? "S7: unknown pair name must exit 2"

# S7b: --only-pair without a value -> exit 2, nothing logged
before=$(cat "$BISYNC_LOG" 2>/dev/null)
run_runner --only-pair
assert_exit_code 2 $? "S7b: --only-pair without a value must exit 2"
assert_equals "$before" "$(cat "$BISYNC_LOG" 2>/dev/null)" \
    "S7b: --only-pair without a value writes nothing to the log"

# S8: lost listings are reported, never auto-fixed
find "$BISYNC_WORKDIR" -maxdepth 1 -type f -name '*alpha*' -delete
run_runner
rc=$?
if [[ "$rc" -ne 0 ]]; then
    assert_equals "" "" "S8: lost listings reported as a failure (exit $rc)"
else
    assert_equals "non-zero" "0" "S8: lost listings must be reported as a failure"
fi
s8=$(newlog)
assert_contains "$s8" "pair[alpha] start regular" \
    "S8: alpha runs regular after lost listings"
assert_not_contains "$s8" "pair[alpha] start --resync" \
    "S8: lost listings must never trigger auto-resync"
assert_contains "$s8" "pass exit=1 failed=alpha" \
    "S8: failed pair listed in pass exit line"

# S9: explicit --resync re-baselines every pair
run_runner --resync
assert_exit_code 0 $? "S9: explicit --resync must succeed"
s9=$(newlog)
assert_contains "$s9" "pair[alpha] start --resync" \
    "S9: alpha re-baselined with --resync"
assert_contains "$s9" "pair[.] start --resync" \
    "S9: root pair re-baselined with --resync"

# S10: log rotation above BISYNC_LOG_MAX_BYTES
printf 'PADDING%s\n' "$(head -c 3000 /dev/zero | tr '\0' 'x')" >> "$BISYNC_LOG"
BISYNC_LOG_MAX_BYTES=2000 run_runner
assert_exit_code 0 $? "S10: run after log growth must succeed"
assert_file_exists "$BISYNC_LOG.1" "S10: rotated log exists"
assert_contains "$(cat "$BISYNC_LOG.1")" "PADDING" \
    "S10: rotated log keeps the old content"
assert_file_exists "$BISYNC_LOG" "S10: new log exists"
assert_not_contains "$(cat "$BISYNC_LOG")" "PADDING" \
    "S10: new log does not keep the old content"

print_test_summary
