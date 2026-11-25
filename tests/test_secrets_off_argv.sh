#!/usr/bin/env bash
# Behavioural tests for task 14: secrets must never appear in curl's argv,
# and the mount monitor must report a dead rclone mount as fail.
#
# Covers (nothing real is called; curl and timeout are stubs):
#   - P1 probe_mount fails at once on a path with no rclone FUSE entry
#   - P2 probe_mount is ok on a path listed as a fuse.rclone mount
#   - P3 probe_mount fails when the table lists the path but it is gone
#   - N1 notify() sends the bot token via curl config on stdin, not argv
#   - N2 notify() sends nothing without credentials
#   - kuma_status / zerotier_clients keep their keys off curl argv in
#     both bash and zsh
#
# The tree under test (the two scripts) is ROOT, overridable via
# SECRETS_OFF_ARGV_ROOT for the work copies.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
        echo "  Found: $needle"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

ROOT="${SECRETS_OFF_ARGV_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

echo "========================================"
echo "Secrets Off Argv Tests"
echo "========================================"
echo ""

# --- mount monitor: source the copy in the test shell
MONITOR="$ROOT/scripts/tools/storagebox_mount_monitor.sh"
set +e
# shellcheck source=scripts/tools/storagebox_mount_monitor.sh
source "$MONITOR"

# P1: no mount entry -> fail at once (no waiting)
: > "$T/mounts"
mkdir -p "$T/plain"
MOUNTS_FILE="$T/mounts"
t0=$(date +%s)
p1=$(probe_mount "$T/plain")
t1=$(date +%s)
assert_equals "fail" "$p1" "P1: path without an rclone FUSE entry probes as fail"
if [[ $((t1 - t0)) -le 2 ]]; then
    echo -e "${GREEN}✓${NC} P1: fail returns within 2 seconds ($((t1 - t0))s)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} P1: fail returns within 2 seconds (took $((t1 - t0))s)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

# P2: mounted per the table and listable -> ok
printf 'hetzner-storagebox: %s fuse.rclone rw,nosuid,nodev 0 0\n' \
    "$T/mp" > "$T/mounts"
mkdir -p "$T/mp"
p2=$(probe_mount "$T/mp")
assert_equals "ok" "$p2" "P2: fuse.rclone mount that lists probes as ok"

# P3: listed in the table but the path does not exist -> fail
printf 'hetzner-storagebox: %s fuse.rclone rw,nosuid,nodev 0 0\n' \
    "$T/ghost" > "$T/mounts"
p3=$(probe_mount "$T/ghost")
assert_equals "fail" "$p3" "P3: table entry without the path probes as fail"

# N1: the bot token goes to curl through config on stdin, never argv
cat > "$T/curlstub" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$T/curl.args"
cat > "$T/curl.stdin"
exit 0
EOF
chmod +x "$T/curlstub"

# notify() removes its payload file right after the curl call; a temporary
# rm() function shadows the rm builtin so the file survives for inspection.
rm() { :; }

: > "$T/empty_secrets"
CURL="$T/curlstub"
SECRETS_FILE="$T/empty_secrets"
export TELEGRAM_BOT_TOKEN=SECRETTOKEN123
export TELEGRAM_CHAT_ID=42
notify "mount down"
unset -f rm
assert_not_contains "$(cat "$T/curl.args")" "SECRETTOKEN123" \
    "N1: bot token is not in curl's arguments"
assert_contains "$(cat "$T/curl.stdin")" \
    'url = "https://api.telegram.org/botSECRETTOKEN123/sendMessage"' \
    "N1: bot token travels via curl config on stdin"
last_arg="$(tail -1 "$T/curl.args")"
args_after_config="$(grep -A1 '^--config$' "$T/curl.args" | head -2)"
assert_equals "--config
-" "$args_after_config" \
    "N1: curl args carry --config followed by - as consecutive arguments"
data_file="${last_arg#*@}"
assert_contains "$(cat "$data_file")" "mount down" \
    "N1: payload file carries the message"
/bin/rm -f "$data_file"

# N2: without credentials nothing is sent
unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID
rm -f "$T/curl.args" "$T/curl.stdin"
notify "x"
assert_file_not_exists "$T/curl.args" \
    "N2: no curl invocation without credentials"
assert_file_not_exists "$T/curl.stdin" \
    "N2: no curl stdin without credentials"

# N3: the real curl accepts the configuration form the code produces.
# No network is used: a refused connection on a closed loopback port
# (rc 7) proves the config was parsed; the rejected spelling exits 2.
n3_port=""
n3_rc_good=""
for p in 9 1 2; do
    printf 'url = "http://127.0.0.1:%s/x"\nuser = ":abc"\n' "$p" \
        | curl -s -m 2 --config - -o /dev/null 2>/dev/null
    n3_rc_good=$?
    if [[ "$n3_rc_good" == "7" ]]; then
        n3_port=$p
        break
    fi
done
assert_equals "7" "$n3_rc_good" \
    "N3: real curl accepts --config - (refused on closed port $n3_port)"
printf 'url = "http://127.0.0.1:%s/x"\nuser = ":abc"\n' "$n3_port" \
    | curl -s -m 2 -config - -o /dev/null 2>/dev/null
n3_rc_bad=$?
assert_equals "2" "$n3_rc_bad" \
    "N3: real curl rejects the -config spelling (exit 2)"

# --- functions/monitors: curl + timeout stubs on PATH
mkdir -p "$T/bin" "$T/env/tmp"
cat > "$T/bin/curl" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$T/fn.args"
cat > "$T/fn.stdin"
printf '%s\n' "\$CANNED"
exit 0
EOF
chmod +x "$T/bin/curl"
cat > "$T/bin/timeout" <<EOF
#!/bin/bash
shift 3
exec "\$@"
EOF
chmod +x "$T/bin/timeout"

CHILD='GREEN="" RED="" YELLOW="" BLUE="" NC=""; source "$1/functions/monitors"; kuma_status; zerotier_clients'

run_functions() {
    local shell="$1"
    local kuma_out zt_out
    kuma_out=$(PATH="$T/bin:$PATH" \
        CANNED='monitor_status{monitor_name="site"} 1' \
        UPTIME_KUMA_API=KUMASECRET ZEROTIER_API_KEY=ZTSECRET \
        ZEROTIER_NETWORK_ID=net1 ENV_DIR="$T/env" \
        "$shell" -f -c "$CHILD" _ "$ROOT" 2>&1)
    assert_contains "$kuma_out" "site: " \
        "fn($shell): kuma monitor line is printed"
    zt_out=$(PATH="$T/bin:$PATH" \
        CANNED='[]' \
        UPTIME_KUMA_API=KUMASECRET ZEROTIER_API_KEY=ZTSECRET \
        ZEROTIER_NETWORK_ID=net1 ENV_DIR="$T/env" \
        "$shell" -f -c "$CHILD" _ "$ROOT" 2>&1)
    zt_norm=$(printf '%s\n' "$zt_out" | sed 's/ *| */ | /g')
    assert_contains "$zt_norm" "Client | IP Addresses | Last Seen" \
        "fn($shell): ZeroTier table header is printed"
}

run_functions bash
run_functions zsh

assert_not_contains "$(cat "$T/fn.args")" "KUMASECRET" \
    "fn: kuma API key is not in curl's arguments"
assert_not_contains "$(cat "$T/fn.args")" "ZTSECRET" \
    "fn: ZeroTier key is not in curl's arguments"
assert_contains "$(cat "$T/fn.stdin")" "Authorization: bearer ZTSECRET" \
    "fn: ZeroTier key travels via curl config on stdin"

print_test_summary
exit $?
