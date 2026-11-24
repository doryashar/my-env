#!/usr/bin/env bash
# Behavioural tests for scripts/storagebox/mount-check.sh
# (stub findmnt/lsblk/notify-send, temp dir; nothing under ~/logs).
#
# Covers:
#   - healthy mount with matching UUID: exit 0, marker removed, no log
#   - missing path: exit 1, logged, marker created, notified
#   - dir that is not a mountpoint: exit 1
#   - wrong disk UUID (replug case): exit 2, logged
#   - works without notify-send installed
#   - no hardcoded /dev/sd device names
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${MOUNT_CHECK_SCRIPT:-$SCRIPT_DIR/../scripts/storagebox/mount-check.sh}"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "Mount Check Tests"
echo "========================================"
echo ""

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/bin" "$T/mp"
cat > "$T/bin/findmnt" <<'EOF'
#!/bin/bash
if [ -z "${STUB_SRC:-}" ]; then
    exit 1
fi
printf '%s\n' "$STUB_SRC"
EOF
cat > "$T/bin/lsblk" <<'EOF'
#!/bin/bash
printf '%s\n' "$STUB_UUID"
EOF
cat > "$T/bin/notify-send" <<EOF
#!/bin/bash
echo "\$*" >> "$T/notify.txt"
EOF
chmod +x "$T/bin/findmnt" "$T/bin/lsblk" "$T/bin/notify-send"

export STUB_SRC="/dev/sdb1" STUB_UUID="AAAA-BBBB"
PATH="$T/bin:$PATH"

run() {
    MOUNT_CHECK_LOG="$T/mount-check.log" MOUNT_CHECK_MARKER="$T/marker" \
        bash "$SCRIPT" "$@" > "$T/run.out" 2>&1
}

reset() {
    rm -f "$T/mount-check.log" "$T/marker" "$T/notify.txt"
}

logged() { cat "$T/mount-check.log" 2>/dev/null; }

notified() {
    if [[ -f "$T/notify.txt" ]]; then
        wc -l < "$T/notify.txt"
    else
        echo 0
    fi
}

# S1: healthy mount, matching UUID
reset
STUB_SRC=/dev/sdb1 STUB_UUID=AAAA-BBBB
touch "$T/marker"
run "$T/mp" AAAA-BBBB
assert_exit_code 0 $? "S1: healthy mount must exit 0"
assert_file_not_exists "$T/mount-check.log" "S1: no log line written"
assert_file_not_exists "$T/marker" "S1: marker removed"

# S2: missing path
reset
run "$T/nope" AAAA-BBBB
assert_exit_code 1 $? "S2: missing path must exit 1"
assert_contains "$(logged)" "MOUNT-LOST: path $T/nope missing" \
    "S2: log records the missing path"
assert_file_exists "$T/marker" "S2: marker created"
assert_equals "1" "$(notified)" "S2: one notification sent"

# S3: exists but is not a mountpoint
reset
mkdir -p "$T/plain"
STUB_SRC=""
run "$T/plain" AAAA-BBBB
assert_exit_code 1 $? "S3: stale dir must exit 1"
assert_contains "$(logged)" "not a mountpoint" \
    "S3: log says not a mountpoint"

# S4: wrong disk (replug)
reset
STUB_SRC=/dev/sdc1 STUB_UUID=CCCC-DDDD
run "$T/mp" AAAA-BBBB
assert_exit_code 2 $? "S4: wrong disk must exit 2"
assert_contains "$(logged)" "CCCC-DDDD" "S4: log shows the actual uuid"
assert_contains "$(logged)" "AAAA-BBBB" "S4: log shows the expected uuid"

# S5: works without notify-send installed
reset
PATH=/usr/bin:/bin
run "$T/nope" AAAA-BBBB
assert_exit_code 1 $? "S5: missing path must exit 1 without notify-send"
assert_contains "$(logged)" "MOUNT-LOST: path $T/nope missing" \
    "S5: same log line without notify-send"

# S6: no hardcoded device names
assert_equals "0" "$(grep -c '/dev/sd' "$SCRIPT" || true)" \
    "S6: no hardcoded /dev/sd device in the script"

print_test_summary
