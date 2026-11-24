#!/usr/bin/env bash
# Behavioural tests for scripts/storagebox/status-update.sh
# (temp log, stub sender; nothing real is touched).
#
# Covers:
#   - empty log -> UNHEALTHY "no completed pass yet", marker created
#   - log without pass lines -> no crash; weekly shows exit=none at never
#   - healthy pass -> RECOVERED notice, marker removed; silent afterwards
#   - failed pass -> UNHEALTHY naming the pair; repeats are not loud
#   - stale pass start -> UNHEALTHY "no sync pass started for"
#   - in-progress pass without a completed one: healthy only while running
#   - weekly mode always sends, with the recent pass counts
#   - a running pass never hides a failed last pass
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${STATUS_SCRIPT:-$SCRIPT_DIR/../scripts/storagebox/status-update.sh}"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "StorageBox Status Tests"
echo "========================================"
echo ""

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

: > "$T/bisync.log"
cat > "$T/send.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$(printf '%s' "\$*" | tr '\n' ' ')" >> "$T/sent.txt"
EOF
chmod +x "$T/send.sh"

export STATUS_LOG="$T/bisync.log"
export STATUS_MARKER="$T/unhealthy"
export STATUS_SEND="$T/send.sh"
export STATUS_RUNNING=0
export STATUS_SNAPSHOT_BYTES=209715200

stamp() { date -Is; }

reset_log() { : > "$T/bisync.log"; }

pass_ok() {
    {
        echo "$(stamp) pass start"
        echo "$(stamp) pair[alpha] start regular"
        echo "$(stamp) pair[alpha] exit=0"
        echo "$(stamp) pass exit=0 failed="
    } >> "$T/bisync.log"
}

pass_fail() {
    local name="$1" code="$2"
    {
        echo "$(stamp) pass start"
        echo "$(stamp) pair[$name] start regular"
        echo "$(stamp) pair[$name] exit=$code"
        echo "$(stamp) pass exit=1 failed=$name"
    } >> "$T/bisync.log"
}

sent() { cat "$T/sent.txt" 2>/dev/null; }

sent_count() {
    if [[ -f "$T/sent.txt" ]]; then
        wc -l < "$T/sent.txt"
    else
        echo 0
    fi
}

run_mode() {
    bash "$SCRIPT" "$1" > "$T/run.out" 2>&1
}

assert_starts_with() {
    local line="$1" prefix="$2" message="$3"
    if [[ "$line" == "$prefix"* ]]; then
        echo -e "${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $message"
        echo "  Line starts with: ${line:0:20}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# S1: empty log -> UNHEALTHY, marker created
run_mode auto2h
assert_exit_code 0 $? "S1: auto2h on an empty log must exit 0"
assert_equals "1" "$(sent_count)" "S1: one message sent"
assert_contains "$(sent)" "UNHEALTHY" "S1: message says UNHEALTHY"
assert_contains "$(sent)" "no completed pass yet" \
    "S1: message names the reason"
assert_file_exists "$T/unhealthy" "S1: unhealthy marker created"

# S1b: log with content but no pass lines -> no crash, still unhealthy
{
    echo "$(stamp) INFO  : rclone v1.69.2 starting bisync"
    echo "$(stamp) INFO  : pair[alpha] : 1234 files to transfer"
    echo "$(stamp) INFO  : pair[alpha] : 5 files copied"
    echo "$(stamp) pair[alpha] start --resync"
} >> "$T/bisync.log"
run_mode auto2h
assert_exit_code 0 $? "S1b: auto2h on a log without pass lines must exit 0"
assert_equals "2" "$(sent_count)" "S1b: exactly one line sent"
assert_contains "$(tail -1 "$T/sent.txt")" "UNHEALTHY" \
    "S1b: message says UNHEALTHY"
assert_contains "$(tail -1 "$T/sent.txt")" "no completed pass yet" \
    "S1b: message names the reason"
rm -f "$T/unhealthy"
run_mode weekly
assert_exit_code 0 $? "S1b: weekly on a log without pass lines must exit 0"
assert_equals "3" "$(sent_count)" "S1b: weekly sends one line"
assert_contains "$(tail -1 "$T/sent.txt")" "exit=none at never" \
    "S1b: weekly reports no completed pass"
assert_contains "$(tail -1 "$T/sent.txt")" "pass started: never" \
    "S1b: weekly reports no pass start"

# S2: healthy pass -> RECOVERED, marker removed
touch "$T/unhealthy"
pass_ok
run_mode auto2h
assert_exit_code 0 $? "S2: auto2h after a healthy pass must exit 0"
assert_equals "4" "$(sent_count)" "S2: exactly one new message"
assert_contains "$(tail -1 "$T/sent.txt")" "RECOVERED" \
    "S2: new message is the RECOVERED notice"
assert_file_not_exists "$T/unhealthy" "S2: unhealthy marker removed"

# S3: healthy again -> silent
run_mode auto2h
assert_exit_code 0 $? "S3: auto2h while healthy must exit 0"
assert_equals "4" "$(sent_count)" "S3: no new message while healthy"

# S4: failed pass -> UNHEALTHY naming the failed pair
pass_fail crops 7
run_mode auto2h
assert_exit_code 0 $? "S4: auto2h after a failed pass must exit 0"
assert_equals "5" "$(sent_count)" "S4: one new message"
assert_contains "$(tail -1 "$T/sent.txt")" "UNHEALTHY" \
    "S4: message says UNHEALTHY"
assert_contains "$(tail -1 "$T/sent.txt")" "crops" \
    "S4: message names the failed pair"
assert_contains "$(tail -1 "$T/sent.txt")" "failed 1" \
    "S4: message counts the failed pair"
assert_file_exists "$T/unhealthy" "S4: unhealthy marker created"

# S5: same failed state -> one new line, without --loud
run_mode auto2h
assert_exit_code 0 $? "S5: auto2h still unhealthy must exit 0"
assert_equals "6" "$(sent_count)" "S5: exactly one new line"
assert_starts_with "$(tail -1 "$T/sent.txt")" "❌" \
    "S5: repeat alert does not start with --loud"

# S5b: third failed run -> again one new line without --loud
run_mode auto2h
assert_exit_code 0 $? "S5b: third failed run must exit 0"
assert_equals "7" "$(sent_count)" "S5b: exactly one new line"
assert_starts_with "$(tail -1 "$T/sent.txt")" "❌" \
    "S5b: repeat alert does not start with --loud"

# S6: healthy pass -> RECOVERED
pass_ok
run_mode auto2h
assert_exit_code 0 $? "S6: auto2h after a healthy pass must exit 0"
assert_equals "8" "$(sent_count)" "S6: exactly one new message"
assert_contains "$(tail -1 "$T/sent.txt")" "RECOVERED" \
    "S6: new message is the RECOVERED notice"
assert_file_not_exists "$T/unhealthy" "S6: unhealthy marker removed"

# S7: stale pass (20h old) -> UNHEALTHY "no sync pass started for"
reset_log
stale=$(date -Is -d '20 hours ago')
{
    echo "$stale pass start"
    echo "$stale pair[alpha] start regular"
    echo "$stale pair[alpha] exit=0"
    echo "$stale pass exit=0 failed="
} >> "$T/bisync.log"
run_mode auto2h
assert_exit_code 0 $? "S7: auto2h on a stale log must exit 0"
assert_equals "9" "$(sent_count)" "S7: one new message"
assert_contains "$(tail -1 "$T/sent.txt")" "UNHEALTHY" \
    "S7: message says UNHEALTHY"
assert_contains "$(tail -1 "$T/sent.txt")" "no sync pass started for" \
    "S7: message names the stale start"
assert_file_exists "$T/unhealthy" "S7: unhealthy marker created"

# S8: in progress without any completed pass
rm -f "$T/unhealthy"
reset_log
echo "$(stamp) pass start" >> "$T/bisync.log"
STATUS_RUNNING=1 run_mode auto2h
assert_exit_code 0 $? "S8a: in progress and running must exit 0"
assert_equals "9" "$(sent_count)" \
    "S8a: no message while a pass is running"
STATUS_RUNNING=0 run_mode auto2h
assert_exit_code 0 $? "S8b: in progress and not running must exit 0"
assert_equals "10" "$(sent_count)" "S8b: one new message"
assert_contains "$(tail -1 "$T/sent.txt")" "no completed pass yet" \
    "S8b: message names the reason"
assert_file_exists "$T/unhealthy" "S8b: unhealthy marker created"

# S9: weekly mode always sends
reset_log
pass_ok
run_mode weekly
assert_exit_code 0 $? "S9a: weekly on a healthy log must exit 0"
assert_equals "11" "$(sent_count)" "S9a: weekly sends one message"
assert_contains "$(tail -1 "$T/sent.txt")" "weekly" \
    "S9a: message is the weekly status"
assert_contains "$(tail -1 "$T/sent.txt")" \
    "recent passes: 1 clean / 0 failed" \
    "S9a: message reports the pass counts"
pass_fail beta 3
run_mode weekly
assert_exit_code 0 $? "S9b: weekly on a failed log must exit 0"
assert_equals "12" "$(sent_count)" "S9b: weekly sends one more message"
assert_contains "$(tail -1 "$T/sent.txt")" "UNHEALTHY" \
    "S9b: message says UNHEALTHY"
assert_contains "$(tail -1 "$T/sent.txt")" \
    "recent passes: 1 clean / 1 failed" \
    "S9b: message reports the pass counts"

# S10: a running pass must not hide a failed last pass
rm -f "$T/unhealthy"
reset_log
pass_fail crops 7
echo "$(stamp) pass start" >> "$T/bisync.log"
STATUS_RUNNING=1 run_mode auto2h
assert_exit_code 0 $? "S10: auto2h with a failed last pass must exit 0"
assert_equals "13" "$(sent_count)" "S10: one new message"
assert_contains "$(tail -1 "$T/sent.txt")" "UNHEALTHY" \
    "S10: a running pass does not hide the failure"
assert_file_exists "$T/unhealthy" "S10: unhealthy marker created"

# S11: the message lists the failed pairs
assert_contains "$(tail -1 "$T/sent.txt")" "failed pairs: crops" \
    "S11: message lists the failed pairs"

print_test_summary
