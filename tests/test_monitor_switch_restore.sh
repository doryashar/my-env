#!/bin/bash

#########################################################################
# Tests for monitor-switch state persistence + restore subcommand
# Stubs the python helper and gsettings; no DBus/GNOME required.
#########################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

MS="$SCRIPT_DIR/../bin/monitor-switch"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export MONITOR_SWITCH_STATE="$TEST_DIR/state/last-profile"
export MONITOR_SWITCH_RESTORE_WAIT=0
export MONITOR_SWITCH_HELPER="$TEST_DIR/helper.sh"
export HELPER_LOG="$TEST_DIR/helper.log"

export HWP_CONN=DP-1
export DEL_CONN=DP-2
export LEN_CONN=DP-3
export ACTIVE_MONS=""
export AVAILABLE_MONS=""

mkdir -p "$TEST_DIR/state" "$TEST_DIR/bin"

# Stub python helper: canned resolve/get-active/get-available answers
# driven by env vars; every invocation logged to $HELPER_LOG.
cat > "$MONITOR_SWITCH_HELPER" <<'EOF'
#!/bin/bash
cmd="$1"; shift
echo "$cmd $*" >> "$HELPER_LOG"
[ -n "$HELPER_FAIL" ] && exit 1
case "$cmd" in
  resolve)
    echo "HWP $HWP_CONN 1920"
    echo "DEL $DEL_CONN 1920"
    echo "LEN $LEN_CONN 5120"
    ;;
  get-active) printf '%s\n' $ACTIVE_MONS ;;
  get-available) printf '%s\n' $AVAILABLE_MONS ;;
  *) exit 0 ;;
esac
exit 0
EOF
chmod +x "$MONITOR_SWITCH_HELPER"

# Stub gsettings (ensure_keybinding must not touch real dconf)
printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/bin/gsettings"
chmod +x "$TEST_DIR/bin/gsettings"
export PATH="$TEST_DIR/bin:$PATH"

run_ms() {
  bash "$MS" "$@"
}

helper_log() { cat "$HELPER_LOG" 2>/dev/null; }

reset_log() { : > "$HELPER_LOG"; }

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
    echo "  In: $haystack"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
}

assert_no_profile_applied() {
  local message="${1:-No profile should be applied}"
  if grep -q '^profile' "$HELPER_LOG" 2>/dev/null; then
    echo -e "${RED}✗${NC} $message"
    echo "  Unexpected profile call: $(grep '^profile' "$HELPER_LOG")"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    echo -e "${GREEN}✓${NC} $message"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
}

# --- Test 1: toggle from profile1 applies profile2 and saves state ------
export ACTIVE_MONS="DP-1 DP-2"
export AVAILABLE_MONS="DP-1 DP-2 DP-3"
reset_log
out=$(run_ms toggle); rc=$?
assert_exit_code 0 "$rc" "toggle from profile1 exits 0"
assert_contains "$out" "Switching to Profile 2" "toggle switches to profile 2"
assert_equals "profile2" "$(cat "$MONITOR_SWITCH_STATE" 2>/dev/null)" \
  "toggle saves 'profile2' to state file"
assert_contains "$(helper_log)" \
  "profile --primary DP-3 --pos DP-3 0 DP-3" \
  "helper applies LEN-only profile"

# --- Test 2: toggle back from profile2 applies profile1 and saves state --
export ACTIVE_MONS="DP-3"
reset_log
out=$(run_ms toggle); rc=$?
assert_exit_code 0 "$rc" "toggle from profile2 exits 0"
assert_equals "profile1" "$(cat "$MONITOR_SWITCH_STATE" 2>/dev/null)" \
  "toggle saves 'profile1' to state file"
assert_contains "$(helper_log)" \
  "profile --primary DP-1 --pos DP-1 0 --pos DP-2 1920 DP-1 DP-2" \
  "helper applies HP+DEL profile"

# --- Test 3: restore re-applies saved profile1 when all monitors present -
printf 'profile1\n' > "$MONITOR_SWITCH_STATE"
export AVAILABLE_MONS="DP-1 DP-2 DP-3"
reset_log
out=$(run_ms restore); rc=$?
assert_exit_code 0 "$rc" "restore exits 0"
assert_contains "$(helper_log)" \
  "profile --primary DP-1 --pos DP-1 0 --pos DP-2 1920 DP-1 DP-2" \
  "restore re-applies saved profile1"
assert_equals "profile1" "$(cat "$MONITOR_SWITCH_STATE")" \
  "restore keeps state as profile1"

# --- Test 4: restore applies available subset when a monitor is missing --
printf 'profile1\n' > "$MONITOR_SWITCH_STATE"
export AVAILABLE_MONS="DP-1"
reset_log
out=$(run_ms restore); rc=$?
assert_exit_code 0 "$rc" "restore with missing monitor exits 0"
assert_contains "$(helper_log)" "profile --primary DP-1 --pos DP-1 0 DP-1" \
  "restore applies HP-only subset"

# --- Test 5: restore does nothing when profile monitors are absent -------
printf 'profile2\n' > "$MONITOR_SWITCH_STATE"
export AVAILABLE_MONS="DP-1 DP-2"
reset_log
out=$(run_ms restore); rc=$?
assert_exit_code 0 "$rc" "restore with no expected monitors exits 0"
assert_no_profile_applied "restore with LEN absent applies nothing"

# --- Test 6: restore without state file is a quiet no-op -----------------
rm -f "$MONITOR_SWITCH_STATE"
reset_log
out=$(run_ms restore); rc=$?
assert_exit_code 0 "$rc" "restore without state file exits 0"
assert_contains "$out" "No saved profile" "restore reports no saved profile"
assert_no_profile_applied "restore without state applies nothing"

# --- Test 7: custom enable saves and restores connector list -------------
export AVAILABLE_MONS="DP-1 DP-3"
reset_log
out=$(run_ms enable DP-1 DP-3); rc=$?
assert_exit_code 0 "$rc" "enable custom set exits 0"
assert_equals "custom:DP-1 DP-3" "$(cat "$MONITOR_SWITCH_STATE")" \
  "enable saves 'custom:DP-1 DP-3' to state file"
reset_log
out=$(run_ms restore); rc=$?
assert_exit_code 0 "$rc" "restore of custom set exits 0"
assert_contains "$(helper_log)" "profile DP-1 DP-3" \
  "restore re-applies custom set"

# --- Test 8: custom restore is all-or-nothing ----------------------------
export AVAILABLE_MONS="DP-1"
reset_log
out=$(run_ms restore); rc=$?
assert_exit_code 0 "$rc" "custom restore with missing monitor exits 0"
assert_no_profile_applied "custom restore applies nothing when incomplete"

# --- Test 9: restore skips keybinding registration -----------------------
printf 'profile1\n' > "$MONITOR_SWITCH_STATE"
export AVAILABLE_MONS="DP-1 DP-2"
reset_log
out=$(run_ms restore); rc=$?
assert_not_contains "$out" "Keybinding registered" \
  "restore does not touch gsettings keybinding"

# --- Test 10: failed apply exits non-zero and leaves state untouched ----
printf 'profile1\n' > "$MONITOR_SWITCH_STATE"
export AVAILABLE_MONS="DP-1 DP-2"
export HELPER_FAIL=1
reset_log
out=$(run_ms enable DP-1); rc=$?
assert_not_equals 0 "$rc" "failed apply exits non-zero"
assert_contains "$(helper_log)" "profile DP-1" "failed apply still attempts the call"
assert_equals "profile1" "$(cat "$MONITOR_SWITCH_STATE")" \
  "failed apply does not overwrite saved state"
unset HELPER_FAIL

print_test_summary
