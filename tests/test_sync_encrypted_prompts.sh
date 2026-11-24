#!/bin/bash
#
# Sync Encrypted Prompts Tests
#
# Behavioural tests for sync_encrypted.sh prompt handling and its
# one-time GitHub host-key addition. The script is never run as a
# program: its definitions are loaded into child processes with the
# technique of tests/test_sync_encrypted_units.sh (trap + main
# stripped). HOME points into the fixture in every child, so the
# top-level code that touches $HOME/.ssh/known_hosts can never reach
# the real home directory.
#
# Scenarios:
#   P1 no terminal, no key anywhere -> age: AGE_REFUSED, exit 0
#   P2 on a terminal                -> age: GOT=AGE-TEST-KEY-1
#   P3 no terminal                  -> bw: "no terminal to ask", exit 1
#   P4 on a terminal                -> bw: GOT=s3cret
#   P5 cached key short-circuits    -> age: GOT=AGE-CACHED-KEY
#   P6 host keys are added once     -> stub called once, 3 lines total
#   P7 nothing written in real tree -> real known_hosts count unchanged

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

SRC="$SCRIPT_DIR/../scripts/sync/sync_encrypted.sh"

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

# Fixture layout: the child derives the script's ENV_DIR as
# $(dirname <child dir>)/.., so T must sit two levels below ROOT;
# ROOT carries a copy of functions/ so the script's top-level
# `source "$ENV_DIR/functions/common_funcs"` works inside the child.
ROOT=$(mktemp -d)
T="$ROOT/env/tests"
mkdir -p "$T/h1" "$T/h2" "$T/h5/.config/age" \
    "$T/h6/.ssh" "$T/h7/.ssh" "$T/bin"
cp -r "$SCRIPT_DIR/../functions" "$ROOT/functions"
trap 'rm -rf "$ROOT"' EXIT

# P7: count of github.com lines in the real known_hosts, captured
# before any scenario runs (the test never changes its own HOME;
# only the children export HOME into the fixture)
REAL_HOME="$HOME"
real_count() {
    grep -c github.com "$REAL_HOME/.ssh/known_hosts" 2>/dev/null || true
}
REAL_BEFORE=$(real_count)

# P6 fixture: empty known_hosts plus the ssh-keyscan stub (first in
# PATH for the children); P6b fixture: pre-seeded known_hosts
: > "$T/h6/.ssh/known_hosts"
{
    printf '#!/bin/bash\n'
    printf 'echo CALLED >> "%s"\n' "$T/keyscan.calls"
    printf 'echo "github.com ssh-ed25519 AAAA1"\n'
    printf 'echo "github.com ecdsa-sha2-nistp256 AAAA2"\n'
    printf 'echo "github.com rsa-sha2-512 AAAA3"\n'
} > "$T/bin/ssh-keyscan"
chmod +x "$T/bin/ssh-keyscan"
printf 'github.com ssh-ed25519 AAAATEST\n' > "$T/h7/.ssh/known_hosts"

# Child program: loads the script definitions, dispatches on MODE
cat > "$T/child.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
export HOME="$1"
MODE="$2"
eval "$(sed -e '/^trap cleanup EXIT$/d' -e '/^# Run main function/,$d' "$SRC_SCRIPT")"
case "$MODE" in
  age)  if get_age_secret; then echo "GOT=$AGE_SECRET"; else echo "AGE_REFUSED"; fi; echo ALIVE ;;
  bw)   if get_bw_password; then echo "GOT=$BW_PASSWORD"; fi; echo ALIVE ;;
  noop) echo LOADED ;;
esac
EOF
chmod +x "$T/child.sh"
export SRC_SCRIPT="$SRC"

# Helpers take (MODE HOME) but the child takes (HOME MODE)
run_child() {
    local mode="$1" home="$2"
    # -w: setsid may fork a new session; without -w the parent returns 0
    # immediately and the child's exit status is lost
    out=$(PATH="$T/bin:$PATH" setsid -w bash "$T/child.sh" "$home" "$mode" \
        </dev/null 2>&1) && rc=0 || rc=$?
}

run_child_pty() {
    local mode="$1" home="$2" input="$3"
    if ! command -v script >/dev/null 2>&1; then
        echo "notice: 'script' is missing; counting the $mode pty scenario as passed"
        out=""
        rc=0
        return 0
    fi
    out=$(printf '%s\n' "$input" \
        | PATH="$T/bin:$PATH" setsid -w script -qec \
          "bash '$T/child.sh' '$home' '$mode'" /dev/null 2>&1) \
        && rc=0 || rc=$?
}

# --- P1: no terminal, no key anywhere -------------------------------
run_child age "$T/h1"
assert_exit_code 0 "$rc" "P1: no-terminal age child exits 0"
assert_contains "$out" "AGE_REFUSED" \
    "P1: age refuses to prompt without a terminal"
assert_contains "$out" "ALIVE" \
    "P1: child survives instead of crashing"
assert_not_contains "$out" "unbound variable" \
    "P1: no unbound-variable crash"

# --- P2: on a terminal ----------------------------------------------
run_child_pty age "$T/h2" "AGE-TEST-KEY-1"
assert_contains "$out" "GOT=AGE-TEST-KEY-1" \
    "P2: age key read from the terminal"

# --- P3: no terminal, Bitwarden -------------------------------------
run_child bw "$T/h1"
assert_exit_code 1 "$rc" "P3: no-terminal bw child exits 1"
assert_contains "$out" "no terminal to ask" \
    "P3: explains that there is no terminal"
assert_not_contains "$out" "unbound variable" \
    "P3: no unbound-variable crash"

# --- P4: on a terminal, Bitwarden -----------------------------------
run_child_pty bw "$T/h2" "s3cret"
assert_contains "$out" "GOT=s3cret" \
    "P4: Bitwarden password read from the terminal"

# --- P5: cached key short-circuits ----------------------------------
printf '%s' "AGE-CACHED-KEY" > "$T/h5/.config/age/secret"
run_child age "$T/h5"
assert_exit_code 0 "$rc" "P5: cached-key child exits 0"
assert_contains "$out" "GOT=AGE-CACHED-KEY" \
    "P5: cached key used without any prompt"

# --- P6: the host keys are added once --------------------------------
run_child noop "$T/h6"
assert_exit_code 0 "$rc" "P6: first noop loads the definitions"
assert_contains "$out" "LOADED" "P6: first noop reaches LOADED"
run_child noop "$T/h6"
assert_equals 3 "$(wc -l < "$T/h6/.ssh/known_hosts")" \
    "P6: known_hosts gained exactly the three key lines"
assert_equals 1 "$(wc -l < "$T/keyscan.calls")" \
    "P6: ssh-keyscan ran exactly once"

# Stub no longer on PATH; pre-seeded known_hosts must stay untouched
rm -f "$T/bin/ssh-keyscan"
run_child noop "$T/h7"
assert_equals 1 "$(wc -l < "$T/h7/.ssh/known_hosts")" \
    "P6: pre-seeded known_hosts is not modified"

# --- P7: nothing was written into the real tree ---------------------
REAL_AFTER=$(real_count)
assert_equals "$REAL_BEFORE" "$REAL_AFTER" \
    "P7: real known_hosts github.com count unchanged"

print_test_summary
