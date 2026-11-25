#!/usr/bin/env bash
# Behavioural tests for scripts/sync/secrets_health.sh (task 18).
#
# Nothing real is sent: a stub sender appends to $T/sent.txt and can be
# made to fail via SEND_RC. The unit files are checked statically.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export T

SCRIPT="${SECRETS_SCRIPT:-$SCRIPT_DIR/../scripts/sync/secrets_health.sh}"
mkdir -p "$T/env/var"

# stub sender: records its arguments, fails when SEND_RC is set
cat > "$T/send.sh" <<'STUB'
#!/bin/bash
echo "$*" >> "$T/sent.txt"
exit "${SEND_RC:-0}"
STUB
chmod +x "$T/send.sh"

OUT=""
RC=0
run() {
    OUT="$(ENV_DIR="$T/env" \
        SECRETS_HASH_FILE="$T/env/var/local_hashes" \
        SECRETS_SEND="$T/send.sh" \
        SECRETS_ENV_FILE="$T/does-not-exist" \
        SECRETS_PING_FILE="$T/ping" \
        bash "$SCRIPT" 2>&1)"
    RC=$?
}
sent() {
    if [ -f "$T/sent.txt" ]; then
        wc -l < "$T/sent.txt"
    else
        echo 0
    fi
}

# --- S1: no hash file -----------------------------------------------------------
run
assert_exit_code 2 "$RC" "S1: no hash file exits 2"
assert_contains "$OUT" "no secrets backup has ever run" "S1: missing-backup message"
assert_equals "1" "$(sent)" "S1: one message sent"
assert_contains "$(cat "$T/sent.txt")" "--loud" "S1: send used --loud"
assert_contains "$(cat "$T/sent.txt")" "var/local_hashes" "S1: message names the missing file"
assert_file_exists "$T/ping" "S1: ping file created after a successful send"

# --- S2: fresh -------------------------------------------------------------------
touch "$T/env/var/local_hashes"
run
assert_exit_code 0 "$RC" "S2: fresh backup exits 0"
assert_contains "$OUT" "secrets backup is 0h old" "S2: fresh message"
assert_equals "1" "$(sent)" "S2: no new message"

# --- S3: stale ---------------------------------------------------------------------
touch -d "5 days ago" "$T/env/var/local_hashes"
run
assert_exit_code 1 "$RC" "S3: stale backup exits 1"
assert_contains "$OUT" "STALE" "S3: stale message"
assert_contains "$OUT" "5 days" "S3: age in days reported"
assert_equals "1" "$(sent)" "S3: no new message (ping younger than a day)"

# --- S4: ping older than a day ---------------------------------------------------------
touch -d "25 hours ago" "$T/ping"
run
assert_exit_code 1 "$RC" "S4: stale with old ping exits 1"
assert_equals "2" "$(sent)" "S4: one more message sent"
last_line="$(tail -n 1 "$T/sent.txt")"
assert_equals "yes" "$( [[ "$last_line" == '--loud 🔒'* ]] && echo yes || echo no)" \
    "S4: new send starts with --loud 🔒"

# --- S5: sending off --------------------------------------------------------------------
export SECRETS_NOTIFY=0
run
unset SECRETS_NOTIFY
assert_exit_code 1 "$RC" "S5: notifying off still exits 1"
assert_equals "2" "$(sent)" "S5: nothing sent"

# --- S6: a failing sender does not change the exit code -----------------------------------
export SEND_RC=1
touch -d "25 hours ago" "$T/ping"
ping_mtime_before=$(stat -c %Y "$T/ping")
run
unset SEND_RC
assert_exit_code 1 "$RC" "S6: failing sender does not change the exit code"
assert_equals "3" "$(sent)" "S6: the send was attempted"
assert_equals "$ping_mtime_before" "$(stat -c %Y "$T/ping")" \
    "S6: ping file not re-created after a failed send"

# --- S7: custom limit ---------------------------------------------------------------------
export SECRETS_MAX_AGE_HOURS=1
touch -d "2 hours ago" "$T/env/var/local_hashes"
run
unset SECRETS_MAX_AGE_HOURS
assert_exit_code 1 "$RC" "S7: two hours old with a one-hour limit exits 1"

# --- S8: the unit files ---------------------------------------------------------------------
timer_file="$SCRIPT_DIR/../config/systemd-user/secrets-health.timer"
service_file="$SCRIPT_DIR/../config/systemd-user/secrets-health.service"
assert_contains "$(cat "$timer_file")" "OnCalendar=*-*-* 09:30:00" "S8: timer calendar"
assert_contains "$(cat "$timer_file")" "WantedBy=timers.target" "S8: timer install target"
assert_contains "$(cat "$service_file")" "ExecStart=%h/env/scripts/sync/secrets_health.sh" "S8: service ExecStart"
assert_contains "$(cat "$service_file")" "Type=oneshot" "S8: service type"

# --- results -------------------------------------------------------------------------------
if print_test_summary; then
    exit 0
fi
exit 1
