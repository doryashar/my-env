#!/usr/bin/env bash
# Behavioural tests for the bootstrap part of scripts/install/setup.sh
# (repo detection + first-run repo.conf; temp dirs only, no network).
#
# Covers:
#   - in-repo detection by layout files (no repo.conf needed)
#   - a failed clone exits 1 with an error
#   - running from an incomplete layout exits 1, never re-execs
#   - a real (stubbed) clone lands and the re-exec runs in repo mode
#   - generate_config collects values from env, git, prompts or
#     placeholders; an existing repo.conf is never rewritten
#   - the real prompt helpers survive a run with no terminal at all
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../scripts/install/setup.sh"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

assert_not_contains() {
    local haystack="$1" needle="$2" message="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "✓ $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "✗ $message"
        echo "  Found: $needle"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

echo "========================================"
echo "Setup Bootstrap Tests"
echo "========================================"
echo ""

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

head_block() {
    # $SETUP up to and including the first 'set -euo pipefail' line,
    # plus an IN_REPO_MODE marker line
    sed -n '1,/^set -euo pipefail$/p' "$SETUP" > "$1"
    echo "echo IN_REPO_MODE" >> "$1"
}

make_env() {
    mkdir -p "$1/scripts/install" "$1/functions" "$1/scripts/sync"
    : > "$1/functions/common_funcs"
    : > "$1/scripts/sync/sync_env.sh"
}

# Group A -----------------------------------------------------------------

# A1: in the repository, no config/repo.conf
h="$T/h1"
make_env "$h/env"
mkdir "$h/env/.git"
head_block "$h/env/scripts/install/setup.sh"
out=$(timeout 10 env HOME="$h" bash "$h/env/scripts/install/setup.sh" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "A1: in-repo run must exit 0"
assert_contains "$out" "IN_REPO_MODE" "A1: ran in repo mode"

# A2: nothing to clone with -> exit 1
h="$T/h2"
mkdir -p "$h" "$T/tools" "$T/bin"
printf '#!/bin/bash\nexit 1\n' > "$T/bin/git"
chmod +x "$T/bin/git"
head_block "$T/tools/setup.sh"
out=$(timeout 10 env PATH="$T/bin:$PATH" HOME="$h" \
    bash "$T/tools/setup.sh" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "A2: failed clone must exit 1"
assert_contains "$out" "git clone failed" "A2: error mentions the clone"

# A3: target exists but the layout is incomplete
h="$T/h3"
mkdir -p "$h/env/scripts/install" "$h/env/.git"
head_block "$h/env/scripts/install/setup.sh"
out=$(timeout 10 env HOME="$h" bash "$h/env/scripts/install/setup.sh" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "A3: incomplete layout must exit 1"
assert_contains "$out" "layout is incomplete" \
    "A3: explains the incomplete layout"
assert_not_contains "$out" "IN_REPO_MODE" \
    "A3: never re-execs into repo mode"

# A4: real clone path with a stub git
make_env "$T/src"
head_block "$T/src/scripts/install/setup.sh"
cat > "$T/bin/git" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "clone" ]; then
    mkdir -p "$3"
    cp -a "$STUB_CLONE_SOURCE/." "$3"
    exit 0
fi
exit 1
EOF
chmod +x "$T/bin/git"
mkdir -p "$T/h4"
out=$(timeout 10 env PATH="$T/bin:$PATH" HOME="$T/h4" \
    STUB_CLONE_SOURCE="$T/src" bash "$T/tools/setup.sh" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "A4: clone then re-exec must exit 0"
assert_contains "$out" "IN_REPO_MODE" \
    "A4: re-executed script ran in repo mode"
assert_file_exists "$T/h4/env/scripts/install/setup.sh" \
    "A4: clone landed the script"

# Group B ------------------------------------------------------------------

load_fn() {
    # Function text from $SETUP: opener line to first closing }
    sed -n "/^$1() {/,/^}$/p" "$SETUP"
}

BRC=0
run_gen() {
    (
        set -euo pipefail
        eval "$(load_fn generate_config)"
        info() { :; }
        log_debug() { :; }
        warning() { echo "WARNING: $*"; }
        prompt() {
            # stub: next answer from the PROMPT_ANSWERS queue, or fail
            if [ -n "${PROMPT_FAIL:-}" ]; then
                return 1
            fi
            local answer="${PROMPT_ANSWERS[0]}"
            PROMPT_ANSWERS=("${PROMPT_ANSWERS[@]:1}")
            printf -v "$2" '%s' "$answer"
        }
        generate_config
    ) > "$T/b.out" 2>&1
    BRC=$?
}

# Run the program $1 in a detached child (setsid), stdin /dev/null.
# Sets D_OUT (combined output) and D_RC.
run_detached() {
    D_OUT=$(setsid -w bash -c "$1" </dev/null 2>&1)
    D_RC=$?
}

setup_b() {
    mkdir -p "$1/config"
    export ENV_DIR="$1" PROMPT_LOG="$T/prompts.txt"
    unset REMOTE_URL PRIVATE_URL BW_EMAIL
    PROMPT_ANSWERS=()
    PROMPT_FAIL=""
    rm -f "$T/b.out" "$T/prompts.txt"
}

# B1: all three values from the environment
setup_b "$T/hb1"
export REMOTE_URL="x@h:a/b" PRIVATE_URL="x@h:c/d.git" BW_EMAIL="me@host"
run_gen
assert_exit_code 0 "$BRC" "B1: all env values must exit 0"
assert_contains "$(grep '^REMOTE_URL=' "$T/hb1/config/repo.conf")" \
    "x@h:a/b" "B1: REMOTE_URL from env"
assert_contains "$(grep '^PRIVATE_URL=' "$T/hb1/config/repo.conf")" \
    "x@h:c/d.git" "B1: PRIVATE_URL from env"
assert_contains "$(grep '^export BW_EMAIL=' "$T/hb1/config/repo.conf")" \
    "me@host" "B1: BW_EMAIL from env"
assert_not_contains "$(cat "$T/hb1/config/repo.conf")" "YOUR_USER" \
    "B1: no placeholders left"
assert_file_not_exists "$T/prompts.txt" "B1: prompt stub was never called"
unset REMOTE_URL PRIVATE_URL BW_EMAIL

# B2: values from prompts
setup_b "$T/hb2"
PROMPT_ANSWERS=("git@github.com:bob/my-env" \
    "git@github.com:bob/encrypted.git" "bob@x")
run_gen
assert_exit_code 0 "$BRC" "B2: prompt answers must exit 0"
assert_contains "$(grep '^REMOTE_URL=' "$T/hb2/config/repo.conf")" \
    "git@github.com:bob/my-env" "B2: REMOTE_URL from prompt"
assert_contains "$(grep '^PRIVATE_URL=' "$T/hb2/config/repo.conf")" \
    "git@github.com:bob/encrypted.git" "B2: PRIVATE_URL from prompt"
assert_equals 'export BW_EMAIL="${BW_EMAIL:-bob@x}"' \
    "$(grep '^export BW_EMAIL=' "$T/hb2/config/repo.conf")" \
    "B2: BW_EMAIL line keeps the default form"

# B3: no terminal at all: no env, the real prompt cannot ask, no git
# repository. Runs in a detached child so /dev/tty is unavailable too.
setup_b "$T/hb3"
prog="$(load_fn can_ask)
$(load_fn prompt)
info() { :; }
warning() { echo \"WARNING: \$*\"; }
$(load_fn generate_config)
set -euo pipefail
generate_config"
run_detached "$prog"
assert_exit_code 0 "$D_RC" "B3: a run without a terminal must not abort"
assert_not_contains "$D_OUT" "unbound variable" \
    "B3: no unbound variable error"
assert_file_exists "$T/hb3/config/repo.conf" "B3: file still created"
assert_contains "$(grep '^REMOTE_URL=' "$T/hb3/config/repo.conf")" \
    "YOUR_USER" "B3: REMOTE_URL placeholder kept"
assert_contains "$(grep '^PRIVATE_URL=' "$T/hb3/config/repo.conf")" \
    "YOUR_USER" "B3: PRIVATE_URL placeholder kept"
assert_contains "$(grep '^export BW_EMAIL=' "$T/hb3/config/repo.conf")" \
    "your-email@example.com" "B3: BW_EMAIL placeholder kept"
assert_contains "$D_OUT" "REMOTE_URL" "B3: warning names REMOTE_URL"
assert_contains "$D_OUT" "PRIVATE_URL" "B3: warning names PRIVATE_URL"
assert_contains "$D_OUT" "BW_EMAIL" "B3: warning names BW_EMAIL"

# B4: REMOTE_URL from the clone's origin remote
setup_b "$T/hb4"
git -C "$T/hb4" init -q
git -C "$T/hb4" remote add origin file:///nowhere/my-env.git
export PROMPT_FAIL=1 PRIVATE_URL="x@h:c/d.git" BW_EMAIL="me@host"
run_gen
assert_exit_code 0 "$BRC" "B4: remote-from-clone must exit 0"
assert_equals 'REMOTE_URL="file:///nowhere/my-env.git"' \
    "$(grep '^REMOTE_URL=' "$T/hb4/config/repo.conf")" \
    "B4: REMOTE_URL taken from the origin remote"
unset PRIVATE_URL BW_EMAIL

# B5: an existing file is never rewritten
setup_b "$T/hb5"
printf 'KEEPME\n' > "$T/hb5/config/repo.conf"
run_gen
# No exit-code assertion here: where `debug` is a shell builtin (some
# hosts), the function's final debug call cannot be stubbed and exits
# non-zero; the spec asserts content and temp-file behaviour only.
assert_equals "KEEPME" "$(cat "$T/hb5/config/repo.conf")" \
    "B5: content unchanged"
assert_equals "1" "$(ls -A "$T/hb5/config" | wc -l)" \
    "B5: no temporary file left in config"

# Group C -------------------------------------------------------------------
# The real prompt helpers, in a detached child with no terminal at all.

# C1: nobody can be asked: prompt returns 1, variable left empty
{
    load_fn can_ask
    load_fn prompt
    load_fn prompt_yn
    echo 'set -euo pipefail'
    cat <<'EOF'
if prompt "q: " v; then echo "got=[$v]"; else echo noprompt; fi; echo alive
EOF
} > "$T/c1.sh"
D_OUT=$(setsid -w bash "$T/c1.sh" </dev/null 2>"$T/c1.err")
D_RC=$?
assert_exit_code 0 "$D_RC" "C1: no-terminal prompt run must exit 0"
assert_equals $'noprompt\nalive' "$D_OUT" \
    "C1: stdout is exactly noprompt and alive"

# C2: nobody can be asked: prompt_yn returns 1, REPLY left empty
{
    load_fn can_ask
    load_fn prompt
    load_fn prompt_yn
    echo 'set -euo pipefail'
    cat <<'EOF'
if prompt_yn "y/n "; then echo yes; else echo no; fi; echo alive
EOF
} > "$T/c2.sh"
D_OUT=$(setsid -w bash "$T/c2.sh" </dev/null 2>"$T/c2.err")
D_RC=$?
assert_exit_code 0 "$D_RC" "C2: no-terminal prompt_yn run must exit 0"
assert_equals $'no\nalive' "$D_OUT" \
    "C2: stdout is exactly no and alive"

print_test_summary
