#!/usr/bin/env bash
# Behavioural tests for the camera tools and letmein security fixes.
#
# Covers:
#   - L1 letmein.sh listen_for_incoming_connections binds the given address
#     (127.0.0.1 by default), not 0.0.0.0/[::]
#   - L2 letmein.sh socat addresses bind $host and no dhparam remains
#   - W1 cam_web.py sends no Access-Control-Allow-* headers (preflight 204,
#     unauthenticated 401, authenticated 200)
#   - D1 cam_discover.discover() returns None when nothing verifies; a
#     missing onvif library does not count as verified
#   - C1 cam_ctrl.py cmd_/get_ functions raise CameraError, never SystemExit
#
# No camera is contacted. Servers are started with setsid and stopped with
# kill -TERM -- -<pid>, including when an assertion fails.

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
        echo "  Found: $needle"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

TOOLS_DIR="$ENV_DIR/scripts/tools"

T=$(mktemp -d)

# Servers are started with setsid, which may fork: the session leader is
# not necessarily $!. Track the port instead; the leader is whoever owns
# the listening socket.
L1_PORT=""
W1_PORT=""

kill_server_port() {
    local port="$1"
    local pid pgid
    pid="$(ss -ltnpH "sport = :$port" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1)"
    [[ -n "$pid" ]] || return 0
    pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
    kill -TERM -- "-${pgid:-$pid}" 2>/dev/null || true
}

cleanup_servers() {
    local port
    for port in "$L1_PORT" "$W1_PORT"; do
        [[ -n "$port" ]] || continue
        local i
        for i in $(seq 1 30); do
            ss -ltnH "sport = :$port" >/dev/null 2>&1 && break
            sleep 0.1
        done
        kill_server_port "$port"
    done
}
trap 'cleanup_servers; rm -rf "$T"' EXIT

free_port() {
    python3 - <<'PY'
import socket

s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

echo "========================================"
echo "Security Tools Tests"
echo "========================================"
echo ""

# L1: letmein.sh binds the given address (default 127.0.0.1)
if ! command -v socat &>/dev/null || ! command -v openssl &>/dev/null; then
    skip_test "L1 skipped: socat or openssl is not available"
else
    L1_PORT="$(free_port)"
    setsid bash "$TOOLS_DIR/letmein.sh" \
        listen_for_incoming_connections "$L1_PORT" >/dev/null 2>&1 &

    l1_line=""
    for _ in $(seq 1 100); do
        l1_line="$(ss -ltnH "sport = :$L1_PORT" 2>/dev/null)"
        [[ -n "$l1_line" ]] && break
        sleep 0.1
    done
    l1_addr="$(awk '{print $4}' <<<"$l1_line")"
    assert_equals "127.0.0.1:$L1_PORT" "$l1_addr" \
        "L1: letmein binds 127.0.0.1, not 0.0.0.0/[::]"

    kill_server_port "$L1_PORT"
    L1_PORT=""
fi

# L2: both socat addresses bind $host; no dhparam left
bind_count="$(grep -c 'openssl-listen:.*bind=\$host' "$TOOLS_DIR/letmein.sh")"
assert_equals "2" "$bind_count" "L2: both socat listeners bind \$host"
assert_not_contains "$(cat "$TOOLS_DIR/letmein.sh")" "dhparam" \
    "L2: dhparam references are gone"

# W1: cam_web.py sends no CORS headers
W1_PORT="$(free_port)"
CAM_WEB_TOKEN=tok123 setsid python3 "$TOOLS_DIR/cam_web.py" -p "$W1_PORT" \
    >/dev/null 2>&1 &

w1_up=""
for _ in $(seq 1 100); do
    if curl -s -o /dev/null \
        "http://127.0.0.1:$W1_PORT/api/stream-url" 2>/dev/null; then
        w1_up=1
        break
    fi
    sleep 0.1
done
assert_equals "1" "$w1_up" "W1: cam_web server answers on the free port"

# pre-flight from a foreign origin
curl -s -D "$T/w1_opts.h" -o "$T/w1_opts.b" -X OPTIONS \
    -H "Origin: http://evil.example" \
    -H "Access-Control-Request-Method: POST" \
    "http://127.0.0.1:$W1_PORT/api/move"
w1_status="$(awk 'NR==1{print $2}' "$T/w1_opts.h")"
assert_equals "204" "$w1_status" "W1: preflight answers 204"
assert_not_contains "$(cat "$T/w1_opts.h")" "Access-Control-Allow" \
    "W1: preflight sends no Access-Control-Allow header"

# unauthenticated GET
curl -s -D "$T/w1_401.h" -o "$T/w1_401.b" \
    "http://127.0.0.1:$W1_PORT/api/stream-url"
w1_status="$(awk 'NR==1{print $2}' "$T/w1_401.h")"
assert_equals "401" "$w1_status" "W1: request without token gets 401"
assert_not_contains "$(cat "$T/w1_401.h")" "Access-Control-Allow" \
    "W1: 401 response sends no Access-Control-Allow header"

# authenticated GET
curl -s -D "$T/w1_200.h" -o "$T/w1_200.b" \
    -H "X-Cam-Token: tok123" \
    "http://127.0.0.1:$W1_PORT/api/stream-url"
w1_status="$(awk 'NR==1{print $2}' "$T/w1_200.h")"
assert_equals "200" "$w1_status" "W1: request with token gets 200"
assert_contains "$(cat "$T/w1_200.b")" '"hls"' \
    "W1: stream-url body contains the hls URL"
assert_not_contains "$(cat "$T/w1_200.h")" "Access-Control-Allow" \
    "W1: 200 response sends no Access-Control-Allow header"

# UI page
curl -s -D "$T/w1_ui.h" -o "$T/w1_ui.b" \
    -H "X-Cam-Token: tok123" \
    "http://127.0.0.1:$W1_PORT/"
w1_status="$(awk 'NR==1{print $2}' "$T/w1_ui.h")"
assert_equals "200" "$w1_status" "W1: UI page with token gets 200"
assert_contains "$(tr '[:upper:]' '[:lower:]' < "$T/w1_ui.b")" "<html" \
    "W1: UI page body is the HTML page"
assert_not_contains "$(cat "$T/w1_ui.h")" "Access-Control-Allow" \
    "W1: UI page sends no Access-Control-Allow header"

kill_server_port "$W1_PORT"
W1_PORT=""

# W2: no CORS header left anywhere in the server
cors_count="$(grep -c 'Access-Control-Allow' "$TOOLS_DIR/cam_web.py")"
assert_equals "0" "$cors_count" \
    "W2: cam_web.py contains no Access-Control-Allow header"

# D1: discovery returns None when nothing verifies; missing onvif is not a pass
python3 - "$TOOLS_DIR" >"$T/d1.out" 2>"$T/d1.err" <<'PY'
import importlib
import sys

sys.path.insert(0, sys.argv[1])
import cam_discover

cam_discover.scan_rtsp_hosts = lambda subnet, timeout: ["10.9.9.5"]
cam_discover.verify_onvif = lambda ip, port: False
assert cam_discover.discover(80, subnet="10.9.9") is None, \
    "unverified candidates must not be returned"

cam_discover.verify_onvif = lambda ip, port: ip == "10.9.9.5"
assert cam_discover.discover(80, subnet="10.9.9") == "10.9.9.5", \
    "the first verifying candidate must be returned"

sys.modules["onvif"] = None
importlib.reload(cam_discover)
assert cam_discover.verify_onvif("10.9.9.5", 80) is False, \
    "a missing onvif library must not count as verified"
print("D1 ok")
PY
assert_exit_code 0 $? "D1: discovery child exits 0"
assert_contains "$(cat "$T/d1.out")" "D1 ok" \
    "D1: all discovery assertions held"

# C1: cam_ctrl library functions raise CameraError, never SystemExit
env -u CAM_USER -u CAM_PASS python3 - "$TOOLS_DIR" >"$T/c1.out" \
    2>"$T/c1.err" <<'PY'
import sys

sys.path.insert(0, sys.argv[1])
import cam_ctrl

assert issubclass(cam_ctrl.CameraError, Exception), \
    "CameraError must be a subclass of Exception"

names = [
    name for name in dir(cam_ctrl)
    if name.startswith(("cmd_", "get_")) and callable(getattr(cam_ctrl, name))
]
assert names, "expected cmd_/get_ functions in cam_ctrl"

exits = []
for name in names:
    fn = getattr(cam_ctrl, name)
    for args in (None,), (None, 1):
        try:
            fn(*args)
        except SystemExit:
            exits.append(f"{name}{args!r}")
        except TypeError:
            pass  # wrong number of arguments
        except Exception:
            pass
assert not exits, f"SystemExit raised: {exits}"
print("C1 ok")
PY
assert_exit_code 0 $? "C1: cam_ctrl child exits 0"
assert_contains "$(cat "$T/c1.out")" "C1 ok" \
    "C1: no cmd_/get_ function raises SystemExit"

print_test_summary
exit $?
