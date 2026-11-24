#!/usr/bin/env bash
# Behavioural tests for scripts/storagebox/resync-until-done.sh
# (stub runner, stub sender, temp dir; nothing real is run).
#
# Covers:
#   - first-try success: completion notice, unit self-disabled, no ping left
#   - repeated failures: hourly ping until success, then completion
#   - RESYNC_MAX_TRIES: gives up with a message and exit 1
#   - a fresh ping file suppresses pings within the hour
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${RESYNC_SCRIPT:-$SCRIPT_DIR/../scripts/storagebox/resync-until-done.sh}"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "Resync Loop Tests"
echo "========================================"
echo ""

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

cat > "$T/runner.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$T/runner.args"
[ -f "$T/skip_first" ] && { rm -f "$T/skip_first"; exit 75; }
n="\$(cat "$T/succeed_after" 2>/dev/null || echo 0)"
t="\$(cat "$T/tries" 2>/dev/null || echo 0)"
t=\$((t + 1))
echo "\$t" > "$T/tries"
[ "\$((t - 1))" -lt "\$n" ] && exit 1
exit 0
EOF
chmod +x "$T/runner.sh"

cat > "$T/send.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$T/sent.txt"
EOF
chmod +x "$T/send.sh"

run() {
    RESYNC_RUNNER="$T/runner.sh" RESYNC_SEND="$T/send.sh" \
        RESYNC_PING_FILE="$T/ping" RESYNC_SLEEP=0 \
        RESYNC_SYSTEMCTL="echo SYSTEMCTL" \
        bash "$SCRIPT" > "$T/run.out" 2>&1
}

reset() {
    rm -f "$T/tries" "$T/runner.args" "$T/sent.txt" \
        "$T/ping" "$T/succeed_after" "$T/skip_first"
}

assert_starts_with() {
    local line="$1" prefix="$2" message="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$line" == "$prefix"* ]]; then
        echo "✓ $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "✗ $message"
        echo "  Does not start with: $prefix"
        echo "  Line: $line"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# S1: success on the first try
reset
run
assert_exit_code 0 $? "S1: first-try success must exit 0"
assert_equals "1" "$(wc -l < "$T/runner.args")" "S1: runner called once"
assert_equals "--resync --max-transfer 2T" "$(head -1 "$T/runner.args")" \
    "S1: runner called with the resync args"
assert_equals "1" "$(wc -l < "$T/sent.txt")" "S1: one message sent"
assert_starts_with "$(head -1 "$T/sent.txt")" "✅" \
    "S1: message is the completion notice"
assert_contains "$(cat "$T/run.out")" \
    "SYSTEMCTL disable storagebox-resync.service" \
    "S1: unit disabled itself"
assert_file_not_exists "$T/ping" "S1: no ping file left"

# S2: hourly pings while failing, then completion
reset
echo 3 > "$T/succeed_after"
run
assert_exit_code 0 $? "S2: success after three failures must exit 0"
assert_equals "4" "$(wc -l < "$T/runner.args")" "S2: runner called four times"
assert_equals "2" "$(wc -l < "$T/sent.txt")" "S2: two messages sent"
assert_starts_with "$(head -1 "$T/sent.txt")" "--loud" \
    "S2: first message is the loud failure ping"
assert_starts_with "$(head -2 "$T/sent.txt" | tail -1)" "✅" \
    "S2: second message is the completion notice"
assert_file_not_exists "$T/ping" "S2: ping file removed"

# S3: RESYNC_MAX_TRIES gives up
reset
echo 1000 > "$T/succeed_after"
export RESYNC_MAX_TRIES=3
run
assert_exit_code 1 $? "S3: giving up must exit 1"
unset RESYNC_MAX_TRIES
assert_equals "3" "$(wc -l < "$T/runner.args")" "S3: runner called three times"
assert_equals "1" "$(wc -l < "$T/sent.txt")" "S3: one message sent"
assert_starts_with "$(head -1 "$T/sent.txt")" "--loud" \
    "S3: message is the failure ping"
assert_contains "$(cat "$T/run.out")" "giving up after 3 tries" \
    "S3: gives up message printed"
assert_file_exists "$T/ping" "S3: ping file left in place"

# S4: a fresh ping file suppresses pings within the hour
reset
echo 1000 > "$T/succeed_after"
touch "$T/ping"
export RESYNC_MAX_TRIES=2
run
assert_exit_code 1 $? "S4: giving up must exit 1"
unset RESYNC_MAX_TRIES
assert_equals "2" "$(wc -l < "$T/runner.args")" "S4: runner called twice"
assert_file_not_exists "$T/sent.txt" "S4: no ping within an hour of the last one"

# S5: a lock-skipped call is not a failed try
reset
echo 0 > "$T/succeed_after"
touch "$T/skip_first"
run
assert_exit_code 0 $? "S5: success after a skipped call must exit 0"
assert_equals "2" "$(wc -l < "$T/runner.args")" \
    "S5: the skipped call plus the successful call"
assert_equals "1" "$(wc -l < "$T/sent.txt")" "S5: one message sent"
assert_starts_with "$(head -1 "$T/sent.txt")" "✅" \
    "S5: message is the completion notice"
assert_file_not_exists "$T/ping" "S5: no ping file left"

# S6: a lock-skipped call does not count against RESYNC_MAX_TRIES
reset
echo 1000 > "$T/succeed_after"
touch "$T/skip_first"
export RESYNC_MAX_TRIES=2
run
assert_exit_code 1 $? "S6: giving up must exit 1"
unset RESYNC_MAX_TRIES
assert_equals "3" "$(wc -l < "$T/runner.args")" \
    "S6: one skipped call plus two failed tries"
assert_equals "1" "$(wc -l < "$T/sent.txt")" "S6: one message sent"

print_test_summary
