#!/usr/bin/env bash
# Tests for P1 fixes identified in docs/code_review_2026-08-28.md
#
# Covers:
#   #52 pingme: curl --config mangles JSON containing quotes; payload must
#       arrive intact, and pingme must not kill set -e callers on failure
#   #53 aliases: snxx must defer $XSIGHT_PASSWORD expansion to call time
#   #54 oref_alert_monitor: daemon must survive null-data alerts and
#       pingme failures (set -euo pipefail daemon killers)
#   #55 show_cam.sh: go2rtc config with RTSP creds must be 0600 and
#       removed on cleanup/stop
#   #56 letmein.sh: listener must default to 127.0.0.1, not 0.0.0.0
#   #58 sync_encrypted.sh: merge-file conflict detection must be live
#       (if-context, not post-hoc $? under errexit)
#   #59 sync_encrypted.sh: git push/pull failures must be handled, not
#       dead code after the fact
#   #60 sync_encrypted.sh: Case-4 stash/pop pair around a guaranteed-clean
#       tree must be gone (stash pop always failed)
#   #61 sync_dotfiles.sh: remove_all_broken_links must survive multiple
#       broken links under set -e

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

WORK_DIR="$(mktemp -d)"
CAPTURE_SERVER_PID=""
CAPTURE_PORT=""

cleanup() {
    [[ -n "$CAPTURE_SERVER_PID" ]] && kill "$CAPTURE_SERVER_PID" 2>/dev/null
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Local HTTP server capturing request bodies to $WORK_DIR/captured.jsonl
# (one JSON body per line). Responds {"ok":true} like the Telegram API.
start_capture_server() {
    [[ -n "$CAPTURE_PORT" ]] && return 0
    python3 - "$WORK_DIR/captured.jsonl" > "$WORK_DIR/server_port" \
        2> "$WORK_DIR/server.err" <<'PY' &
import sys
import http.server

out_path = sys.argv[1]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        with open(out_path, "ab") as f:
            f.write(body + b"\n")
        resp = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)

    def log_message(self, *args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
PY
    CAPTURE_SERVER_PID=$!
    local i
    for i in {1..50}; do
        [[ -s "$WORK_DIR/server_port" ]] && break
        sleep 0.1
    done
    CAPTURE_PORT=$(cat "$WORK_DIR/server_port" 2>/dev/null || echo "")
}

# ----------------------------------------------------------------------------
# #52a: payload with quotes/backslashes must arrive byte-for-byte intact
# ----------------------------------------------------------------------------
test_pingme_delivers_exact_payload_with_quotes() {
    start_capture_server
    if [[ -z "$CAPTURE_PORT" ]]; then
        echo -e "${RED}✗${NC} could not start capture server"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TESTS_RUN=$((TESTS_RUN + 1))
        return
    fi

    local msg='Alert with "quotes", \ backslash and unicode 🚀'
    local expected body rc=0
    expected=$(jq -nc --arg chat_id "4242" --arg text "$msg" \
        '{chat_id:$chat_id, text:$text, disable_notification:true}')

    TELEGRAM_API_URL="http://127.0.0.1:$CAPTURE_PORT" \
    TELEGRAM_BOT_TOKEN="TEST:TOKEN" \
    TELEGRAM_CHAT_ID="4242" \
        bash -c 'source "$1"; pingme "$2"' \
        _ "$ENV_DIR/functions/pingme" "$msg" > /dev/null 2>&1 || rc=$?

    assert_exit_code 0 "$rc" "pingme should succeed against local endpoint"
    body=$(tail -n 1 "$WORK_DIR/captured.jsonl" 2>/dev/null)
    assert_equals "$expected" "$body" \
        "payload must arrive intact (curl config must not mangle JSON)"
}

# ----------------------------------------------------------------------------
# #52b: pingme failure contract: return 1 + clear error (for callers to guard)
# ----------------------------------------------------------------------------
test_pingme_failure_returns_1_with_error() {
    local out rc=0
    out=$(TELEGRAM_API_URL="http://127.0.0.1:9" \
    TELEGRAM_BOT_TOKEN="TEST:TOKEN" \
    TELEGRAM_CHAT_ID="4242" \
        bash -c 'source "$1"; pingme "hi"' \
        _ "$ENV_DIR/functions/pingme" 2>&1) || rc=$?
    assert_exit_code 1 "$rc" "pingme must return 1 on delivery failure"
    assert_contains "$out" "Failed to send" \
        "pingme must report the failure to the caller"
}

# ----------------------------------------------------------------------------
# #53: snxx alias must not bake the password in at definition time
# ----------------------------------------------------------------------------
test_snxx_alias_defers_password_expansion() {
    local out
    out=$(XSIGHT_PASSWORD=P1_SECRET_VALUE zsh -c 'source "$1"; alias snxx' \
        _ "$ENV_DIR/aliases" 2>/dev/null || echo "")
    if [[ "$out" == *P1_SECRET_VALUE* ]]; then
        echo -e "${RED}✗${NC} snxx alias must not contain the password value"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo -e "${GREEN}✓${NC} snxx alias must not contain the password value"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    assert_contains "$out" 'XSIGHT_PASSWORD' \
        "snxx alias must still reference \$XSIGHT_PASSWORD"
}

# ----------------------------------------------------------------------------
# #54a: null-data alert must not kill the daemon; payload must arrive intact
# ----------------------------------------------------------------------------
test_oref_monitor_survives_null_data_alert() {
    start_capture_server
    if [[ -z "$CAPTURE_PORT" ]]; then
        echo -e "${RED}✗${NC} could not start capture server"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TESTS_RUN=$((TESTS_RUN + 1))
        return
    fi

    local fixture="$WORK_DIR/oref_null.json"
    cat > "$fixture" <<'JSON'
{"id": "p1-null-1", "title": "Alert with \"quotes\"", "data": null, "desc": "desc \"q\""}
JSON

    local shim_dir="$WORK_DIR/bin"
    mkdir -p "$shim_dir"
    # Serve the fixture only for the OREF poll; pass everything else
    # (notably pingme's Telegram call) through to the real curl.
    cat > "$shim_dir/curl" <<SHIM
#!/bin/bash
for arg in "\$@"; do
    if [[ "\$arg" == *oref.org.il* ]]; then
        cat "$fixture"
        exit 0
    fi
done
exec /usr/bin/curl "\$@"
SHIM
    chmod +x "$shim_dir/curl"

    local state="$WORK_DIR/oref_state_a"
    local out rc=0
    out=$(env -u MARK PATH="$shim_dir:$PATH" \
        XDG_STATE_HOME="$state" \
        TELEGRAM_API_URL="http://127.0.0.1:$CAPTURE_PORT" \
        TELEGRAM_BOT_TOKEN="TEST:TOKEN" \
        TELEGRAM_CHAT_ID="4242" \
        timeout 3 bash "$ENV_DIR/scripts/tools/oref_alert_monitor.sh" \
        2>&1) || rc=$?

    assert_exit_code 124 "$rc" \
        "monitor must survive null-data alert (124 = still running at timeout)"
    assert_contains "$out" "New alert" "null-data alert must be processed"
    local text
    text=$(tail -n 1 "$WORK_DIR/captured.jsonl" 2>/dev/null \
        | jq -r '.text' 2>/dev/null || echo "")
    assert_equals "🚨 Alert with \"quotes\""$'\n\n'"desc \"q\"" "$text" \
        "alert text (with quotes) must be delivered intact"
}

# ----------------------------------------------------------------------------
# #54b: pingme/network failure must not kill the daemon
# ----------------------------------------------------------------------------
test_oref_monitor_survives_pingme_failure() {
    local fixture="$WORK_DIR/oref_pf.json"
    cat > "$fixture" <<'JSON'
{"id": "p1-pf-1", "title": "PF test", "data": ["Area A"], "desc": ""}
JSON

    local shim_dir="$WORK_DIR/bin_pf"
    mkdir -p "$shim_dir"
    cat > "$shim_dir/curl" <<SHIM
#!/bin/bash
for arg in "\$@"; do
    if [[ "\$arg" == *oref.org.il* ]]; then
        cat "$fixture"
        exit 0
    fi
done
exec /usr/bin/curl "\$@"
SHIM
    chmod +x "$shim_dir/curl"

    local state="$WORK_DIR/oref_state_b"
    local out rc=0
    out=$(env -u MARK PATH="$shim_dir:$PATH" \
        XDG_STATE_HOME="$state" \
        TELEGRAM_API_URL="http://127.0.0.1:9" \
        TELEGRAM_BOT_TOKEN="TEST:TOKEN" \
        TELEGRAM_CHAT_ID="4242" \
        timeout 3 bash "$ENV_DIR/scripts/tools/oref_alert_monitor.sh" \
        2>&1) || rc=$?

    assert_exit_code 124 "$rc" \
        "monitor must survive pingme failure (124 = still running at timeout)"
    assert_contains "$out" "notification failed" \
        "pingme failure must be logged, not fatal"
}

# ----------------------------------------------------------------------------
# #55a: go2rtc config (contains RTSP credentials) must be written 0600
# ----------------------------------------------------------------------------
test_show_cam_config_file_is_private() {
    local script="$ENV_DIR/scripts/tools/show_cam.sh"
    local block="$WORK_DIR/go2rtc_block.sh"
    # Extract the write-block INCLUDING the chmod that follows the heredoc
    sed -n '/^cat > "\$GO2RTC_CONFIG" <<EOF$/,/^chmod 600 "\$GO2RTC_CONFIG"$/p' \
        "$script" > "$block"

    if ! grep -q "streams:" "$block"; then
        echo -e "${RED}✗${NC} could not extract go2rtc config block"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TESTS_RUN=$((TESTS_RUN + 1))
        return
    fi

    local cfg="$WORK_DIR/go2rtc.yaml"
    GO2RTC_CONFIG="$cfg" GO2RTC_PORT=1 GO2RTC_RTSP_PORT=2 \
        WEBRTC_LISTEN=":8443" CAM_USER=u CAM_PASS=secret CAM_HOST=10.0.0.1 \
        bash "$block"

    assert_equals "600" "$(stat -c %a "$cfg" 2>/dev/null || echo missing)" \
        "go2rtc config with RTSP creds must be mode 0600"
}

# ----------------------------------------------------------------------------
# #55b: cleanup() and stop_all() must remove the config file
# ----------------------------------------------------------------------------
test_show_cam_cleanup_removes_config() {
    local script="$ENV_DIR/scripts/tools/show_cam.sh"
    local cleanup_fn stop_fn
    cleanup_fn=$(sed -n '/^cleanup() {/,/^}$/p' "$script")
    stop_fn=$(sed -n '/^stop_all() {/,/^}$/p' "$script")
    assert_contains "$cleanup_fn" 'rm -f "$GO2RTC_CONFIG"' \
        "cleanup() must remove go2rtc config"
    assert_contains "$stop_fn" 'rm -f "$GO2RTC_CONFIG"' \
        "stop_all() must remove go2rtc config"
}

# ----------------------------------------------------------------------------
# #55c: script must restrict default file permissions (umask 077)
# ----------------------------------------------------------------------------
test_show_cam_sets_umask() {
    if grep -q '^umask 077' "$ENV_DIR/scripts/tools/show_cam.sh"; then
        echo -e "${GREEN}✓${NC} show_cam.sh must set umask 077"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} show_cam.sh must set umask 077"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# ----------------------------------------------------------------------------
# #56: listener must bind 127.0.0.1 by default (both listen functions)
# ----------------------------------------------------------------------------
test_letmein_listens_on_localhost_by_default() {
    local count
    count=$(grep -c 'host="${2:-127.0.0.1}"' \
        "$ENV_DIR/scripts/tools/letmein.sh" || true)
    assert_equals "2" "$count" \
        "listen_for_incoming_connections + wait_for_invite must default to 127.0.0.1"
}

# ----------------------------------------------------------------------------
# #61: remove_all_broken_links must survive multiple broken links (set -e)
# ----------------------------------------------------------------------------
test_remove_all_broken_links_survives_multiple() {
    local d="$WORK_DIR/links"
    mkdir -p "$d"
    ln -s "$WORK_DIR/nonexistent-a" "$d/a"
    ln -s "$WORK_DIR/nonexistent-b" "$d/b"

    local out rc=0
    out=$(bash -c '
        set -e
        source "$1"
        remove_all_broken_links "$2"
        echo REMOVE_SURVIVED
    ' _ "$ENV_DIR/scripts/sync/sync_dotfiles.sh" "$d" 2>&1) || rc=$?

    assert_exit_code 0 "$rc" \
        "remove_all_broken_links must survive multiple broken links under set -e"
    assert_contains "$out" "REMOVE_SURVIVED" "script must run to completion"
    # NB: -L, not -f — a dangling symlink fails -f even when it still exists
    if [[ -L "$d/a" ]]; then
        echo -e "${RED}✗${NC} first broken link still exists"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo -e "${GREEN}✓${NC} first broken link removed"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -L "$d/b" ]]; then
        echo -e "${RED}✗${NC} second broken link still exists (no early exit)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo -e "${GREEN}✓${NC} second broken link removed (no early exit)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# ----------------------------------------------------------------------------
# #58: merge-file conflict detection must run inside if-context
# ----------------------------------------------------------------------------
test_sync_encrypted_merge_conflict_detection_is_live() {
    local count
    count=$(grep -c 'if git merge-file' \
        "$ENV_DIR/scripts/sync/sync_encrypted.sh" || true)
    assert_equals "2" "$count" \
        "both merge-file calls must be tested via 'if git merge-file' (errexit-safe)"
}

# ----------------------------------------------------------------------------
# #59: git push/pull failures must be handled inline, not via dead $? checks
# ----------------------------------------------------------------------------
test_sync_encrypted_git_transports_guarded() {
    local pushes pulls
    pushes=$(grep -c 'git push || {' \
        "$ENV_DIR/scripts/sync/sync_encrypted.sh" || true)
    pulls=$(grep -c 'git pull || {' \
        "$ENV_DIR/scripts/sync/sync_encrypted.sh" || true)
    assert_equals "2" "$pushes" "both git push calls must be error-guarded"
    assert_equals "2" "$pulls" "both git pull calls must be error-guarded"
}

# ----------------------------------------------------------------------------
# #60: stash/pop pair around the guaranteed-clean Case-4 tree must be gone
# ----------------------------------------------------------------------------
test_sync_encrypted_stash_pop_removed() {
    local count
    count=$(grep -c 'git stash pop' \
        "$ENV_DIR/scripts/sync/sync_encrypted.sh" || true)
    assert_equals "0" "$count" \
        "git stash pop after clean-tree reset always fails; pair must be removed"
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
    echo "========================================"
    echo "P1 Fix Tests"
    echo "========================================"
    echo ""

    test_pingme_delivers_exact_payload_with_quotes
    test_pingme_failure_returns_1_with_error
    test_snxx_alias_defers_password_expansion
    test_oref_monitor_survives_null_data_alert
    test_oref_monitor_survives_pingme_failure
    test_show_cam_config_file_is_private
    test_show_cam_cleanup_removes_config
    test_show_cam_sets_umask
    test_letmein_listens_on_localhost_by_default
    test_remove_all_broken_links_survives_multiple
    test_sync_encrypted_merge_conflict_detection_is_live
    test_sync_encrypted_git_transports_guarded
    test_sync_encrypted_stash_pop_removed

    echo ""
    print_test_summary
}

main "$@"
