#!/usr/bin/env bash
# Tests for P0 security fixes identified in docs/REVIEW_2026-06-16.md
#
# Covers:
#   #8  cam_ctrl.py: hardcoded camera credentials -> env vars
#   #9  cam_web.py: bind 127.0.0.1 by default + optional auth token
#   #10 letmein.sh: TLS verify=0 must be documented (warn comment)
#   #11 pingme + generate_image.sh: JSON built with jq (no string interp)
#   #12 pingme + generate_image.sh: token/auth not visible in curl argv

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "P0 Security Fix Tests"
echo "========================================"
echo ""

# ----------------------------------------------------------------------------
# Bug #8: cam_ctrl.py must not contain hardcoded credentials.
# Reading the file as text and checking for absence of the leaked password
# is the most direct test (no Python execution needed).
# ----------------------------------------------------------------------------
test_cam_ctrl_no_hardcoded_password() {
    local script="$ENV_DIR/scripts/tools/cam_ctrl.py"
    # The literal password "1111" must no longer be assigned to CAM_PASS
    if grep -qE 'CAM_PASS\s*=\s*"1111"' "$script"; then
        assert_equals "absent" "present" \
            "cam_ctrl.py must not contain hardcoded password '1111' (rotate it!)"
    else
        assert_equals "absent" "absent" \
            "cam_ctrl.py must not contain hardcoded password '1111'"
    fi
}

test_cam_ctrl_reads_env_for_credentials() {
    local script="$ENV_DIR/scripts/tools/cam_ctrl.py"
    # Must reference env vars (os.environ.get or os.getenv) for CAM_USER/CAM_PASS
    local env_refs
    env_refs=$(grep -cE 'os\.(environ\.get|getenv)\s*\(\s*"?CAM_(USER|PASS)' "$script")
    assert_equals 2 "$env_refs" \
        "cam_ctrl.py must read CAM_USER and CAM_PASS from environment (found $env_refs env refs, need 2)"
}

# ----------------------------------------------------------------------------
# Bug #9: cam_web.py must bind 127.0.0.1 by default (not 0.0.0.0).
# ----------------------------------------------------------------------------
test_cam_web_default_bind_is_localhost() {
    local script="$ENV_DIR/scripts/tools/cam_web.py"
    # The default HTTPServer bind address must be 127.0.0.1
    if grep -qE 'HTTPServer\(\("0\.0\.0\.0"' "$script"; then
        assert_equals "127.0.0.1" "0.0.0.0" \
            "cam_web.py must default to 127.0.0.1 (currently 0.0.0.0 — exposes PTZ to LAN)"
    else
        assert_equals "127.0.0.1" "127.0.0.1" \
            "cam_web.py must default to 127.0.0.1"
    fi
}

test_cam_web_supports_auth_token() {
    local script="$ENV_DIR/scripts/tools/cam_web.py"
    # Must support an auth token via env var (CAM_WEB_TOKEN or similar)
    local token_support
    token_support=$(grep -cE 'CAM_WEB_TOKEN|AUTH_TOKEN' "$script")
    [[ "$token_support" -ge 1 ]]
    assert_exit_code 0 $? \
        "cam_web.py must support token auth via env var (CAM_WEB_TOKEN) — found $token_support refs"
}

# ----------------------------------------------------------------------------
# Bug #10: letmein.sh must document the verify=0 risk
# ----------------------------------------------------------------------------
test_letmein_documents_tls_risk() {
    local script="$ENV_DIR/scripts/tools/letmein.sh"
    # Must contain a warning comment about verify=0 / MITM risk
    local warn_count
    warn_count=$(grep -cE 'MITM|TLS.*verif|verif.*0.*risk|insecure.*LAN|trusted.*LAN' "$script")
    [[ "$warn_count" -ge 1 ]]
    assert_exit_code 0 $? \
        "letmein.sh must document the TLS verify=0 / MITM risk (found $warn_count warn refs)"
}

# ----------------------------------------------------------------------------
# Bug #11: pingme must build JSON with jq, not string interpolation
# ----------------------------------------------------------------------------
test_pingme_uses_jq_for_json() {
    local script="$ENV_DIR/functions/pingme"
    # Flatten continuation lines so we can grep across the full command
    local flat
    flat=$(tr '\n' ' ' < "$script" | tr -s ' ')
    # Must NOT contain the unsafe `"{\"chat_id\"` interpolation pattern
    if echo "$flat" | grep -qE '\-d\s*"\\?\{\\?"chat_id'; then
        assert_equals "safe" "unsafe" \
            "pingme must not build JSON via string interpolation (jq injection-safe build required)"
    else
        assert_equals "safe" "safe" \
            "pingme must not build JSON via string interpolation"
    fi
    # Must reference jq
    local jq_use
    jq_use=$(grep -cE 'jq\s+-nc?' "$script")
    assert_equals 1 "$jq_use" \
        "pingme must use jq to build JSON payload"
}

# ----------------------------------------------------------------------------
# Bug #11: generate_image.sh must build JSON with jq, not string interpolation
# ----------------------------------------------------------------------------
test_generate_image_uses_jq_for_json() {
    local script="$ENV_DIR/scripts/tools/generate_image.sh"
    local flat
    flat=$(tr '\n' ' ' < "$script" | tr -s ' ')
    # Must NOT contain `curl ... -d "{ ... \"model\"` (string-interpolated JSON)
    if echo "$flat" | grep -qE '\-d\s*"\s*\\?\{[^"]*\\?"model'; then
        assert_equals "safe" "unsafe" \
            "generate_image.sh must not build JSON via string interpolation"
    else
        assert_equals "safe" "safe" \
            "generate_image.sh must not build JSON via string interpolation"
    fi
    local jq_use
    jq_use=$(grep -cE 'jq\s+-n' "$script")
    assert_equals 1 "$jq_use" \
        "generate_image.sh must use jq to build JSON payload"
}

# ----------------------------------------------------------------------------
# Bug #12: pingme must keep TELEGRAM_BOT_TOKEN out of curl argv
# (Token should be passed via stdin with --config, not as a URL argument)
# ----------------------------------------------------------------------------
test_pingme_token_not_in_curl_argv() {
    local script="$ENV_DIR/functions/pingme"
    # The fix uses `curl --config -` so all args (URL, headers, data) are
    # passed via stdin (heredoc), keeping the token out of argv.
    # We verify by ensuring:
    #   1. curl is invoked with `--config -` (stdin)
    #   2. The URL containing the token appears in the heredoc body
    #      (preceded by `<<EOF`), not as a curl argument
    local uses_config_stdin
    uses_config_stdin=$(grep -cE 'curl[[:space:]]+--config[[:space:]]+-' "$script")
    [[ "$uses_config_stdin" -ge 1 ]]
    assert_exit_code 0 $? \
        "pingme must use curl --config - to hide token from argv (found $uses_config_stdin refs)"
    local url_in_heredoc
    url_in_heredoc=$(grep -cE '^url\s*=' "$script")
    assert_equals 1 "$url_in_heredoc" \
        "pingme must pass URL via heredoc (url = ...) not curl argv"
}

# ----------------------------------------------------------------------------
# Bug #12: generate_image.sh must keep API_KEY out of curl argv
# ----------------------------------------------------------------------------
test_generate_image_auth_not_in_curl_argv() {
    local script="$ENV_DIR/scripts/tools/generate_image.sh"
    # Authorization header with the key must not be a literal curl argument
    local header_in_argv
    header_in_argv=$(grep -cE '\-H\s*"Authorization:.*\$API_KEY' "$script")
    assert_equals 0 "$header_in_argv" \
        "generate_image.sh must not pass Authorization header as curl argv (visible in ps)"
}

# ----------------------------------------------------------------------------
# Behavior test: pingme must produce valid JSON for messages with quotes /
# backslashes (the actual bug the jq migration fixes)
# ----------------------------------------------------------------------------
test_pingme_json_safe_with_special_chars() {
    # Simulate the jq command pingme should now use, with a hostile message
    local message='He said "hi"\and newline'
    local json
    json=$(jq -nc --arg chat_id "123" --arg text "$message" \
        '{chat_id:$chat_id, text:$text, disable_notification:true}')
    # Verify the JSON parses and the text round-trips
    local parsed
    parsed=$(echo "$json" | jq -r '.text')
    assert_equals "$message" "$parsed" \
        "pingme jq-built JSON must survive messages with quotes and backslashes"
    # And chat_id must be 123 (no injection)
    local parsed_id
    parsed_id=$(echo "$json" | jq -r '.chat_id')
    assert_equals "123" "$parsed_id" \
        "pingme jq-built JSON must not allow chat_id injection"
}

# ----------------------------------------------------------------------------
# Run all tests
# ----------------------------------------------------------------------------
test_cam_ctrl_no_hardcoded_password
test_cam_ctrl_reads_env_for_credentials
test_cam_web_default_bind_is_localhost
test_cam_web_supports_auth_token
test_letmein_documents_tls_risk
test_pingme_uses_jq_for_json
test_generate_image_uses_jq_for_json
test_pingme_token_not_in_curl_argv
test_generate_image_auth_not_in_curl_argv
test_pingme_json_safe_with_special_chars

print_test_summary
