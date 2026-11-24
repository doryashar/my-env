#!/bin/bash
#
# Setup Steps Tests
#
# Behavioural tests for three setup.sh steps with every system command
# stubbed: setup_zsh no longer overwrites .zshrc/.zshenv,
# install_pip_packages installs the missing Python tools with pipx
# only, and setup_cron_jobs shows a diff and asks before replacing
# an installed crontab.
#
# The tested functions are extracted from setup.sh by text (load_fn)
# and loaded into subshells; every command they use (chsh, pipx,
# pip3, crontab, ...) is a shell function defined after the function
# text is loaded, so no real system command is ever reached.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

SETUP="$SCRIPT_DIR/../scripts/install/setup.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# Print the text of the function NAME from $SETUP: from the line
# `NAME() {` up to and including the first following line that is
# exactly `}`.
load_fn() {
    awk -v fn="$1" '
        $0 == fn "() {" { in_fn = 1 }
        in_fn { print }
        in_fn && $0 == "}" { exit }
    ' "$SETUP"
}

# Logging stubs: print their text (the repo's logging function is
# log_debug; debug is a bash 5.3 builtin that some migrated scripts
# still call, so stub both)
logging_stubs() {
    info() { printf '%s\n' "$*"; }
    warning() { printf '%s\n' "$*"; }
    debug() { printf '%s\n' "$*"; }
    log_debug() { printf '%s\n' "$*"; }
}

assert_regular_file() {
    local path="$1"
    local message="${2:-$1 is a regular file, not a symlink}"
    if [[ -f "$path" && ! -L "$path" ]]; then
        echo -e "${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# --- G1: setup_zsh leaves existing files alone ----------------------
mkdir -p "$T/env/dotfiles" "$T/home"
printf 'MINE\n' > "$T/env/dotfiles/.zshrc"
printf 'MINE2\n' > "$T/env/dotfiles/.zshenv"
printf 'MINE\n' > "$T/home/.zshrc"
printf 'MINE2\n' > "$T/home/.zshenv"
: > "$T/home/.z4h.zsh"
rm -f "$T/calls"
out=$( (
    eval "$(load_fn setup_zsh)"
    logging_stubs
    command_exists() { return 0; }
    chsh() { echo "CHSH-STUB" >> "$T/calls"; }
    ENV_DIR="$T/env"
    HOME="$T/home"
    SHELL=/bin/bash
    setup_zsh
) 2>&1 ); rc=$?
assert_exit_code 0 "$rc" "G1: setup_zsh exits 0"
assert_regular_file "$T/home/.zshrc" "G1: .zshrc left as a regular file"
assert_equals "MINE" "$(cat "$T/home/.zshrc")" "G1: .zshrc content untouched"
assert_regular_file "$T/home/.zshenv" "G1: .zshenv left as a regular file"
assert_equals "MINE2" "$(cat "$T/home/.zshenv")" "G1: .zshenv content untouched"
assert_equals 1 "$(wc -l < "$T/calls")" \
    "G1: chsh stub reached exactly once"

# --- G2: pipx used for the missing tools only -----------------------
rm -f "$T/calls"
out=$( (
    eval "$(load_fn install_pip_packages)"
    logging_stubs
    command_exists() { [[ "$1" != "pip3" ]]; }
    pipx() {
        echo "pipx $*" >> "$T/calls"
        [[ "$1" == "list" ]] && printf '%s\n' "black 24.10.0" "flake8 7.1.0"
        return 0
    }
    install_pip_packages
) 2>&1 ); rc=$?
assert_exit_code 0 "$rc" "G2: install_pip_packages exits 0"
# The stub records every pipx invocation, so the one
# `pipx list --short` probe is among the recorded lines; the
# install commands must be exactly the three missing tools
assert_equals "pipx install python-lsp-server
pipx install pylint
pipx install neovim-remote" \
    "$(grep '^pipx install' "$T/calls")" \
    "G2: exactly the three missing tools installed via pipx"
if grep -q 'pip3' "$T/calls"; then
    echo -e "${RED}✗${NC} G2: pip3 is never used"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "${GREEN}✓${NC} G2: pip3 is never used"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

# --- G3: pipx missing -----------------------------------------------
rm -f "$T/calls"
out=$( (
    eval "$(load_fn install_pip_packages)"
    logging_stubs
    command_exists() { return 1; }
    pipx() { echo "MUST NOT RUN" >> "$T/calls"; }
    pip3() { echo "MUST NOT RUN" >> "$T/calls"; }
    install_pip_packages
) 2>&1 ); rc=$?
assert_exit_code 0 "$rc" "G3: exits 0 when pipx is missing"
assert_contains "$out" "pipx not found" \
    "G3: explains that pipx is missing"
assert_file_not_exists "$T/calls" "G3: nothing was installed"

# --- Crontab fixture: installed crontab is B, tracked file is A -----
mkdir -p "$T/env/config"
printf 'A\n' > "$T/env/config/crontab"
crontab_stub_a() {
    crontab() {
        if [[ "$1" == "-l" ]]; then
            printf '%s\n' "A"
        else
            echo "REPLACE $*" >> "$T/calls"
        fi
    }
}
crontab_stub_b() {
    crontab() {
        if [[ "$1" == "-l" ]]; then
            printf '%s\n' "B"
        else
            echo "REPLACE $*" >> "$T/calls"
        fi
    }
}

# --- G4: crontab already identical ----------------------------------
rm -f "$T/calls"
out=$( (
    eval "$(load_fn setup_cron_jobs)"
    logging_stubs
    crontab_stub_a
    ENV_DIR="$T/env"
    setup_cron_jobs
) 2>&1 ); rc=$?
assert_exit_code 0 "$rc" "G4: exits 0 when the crontab already matches"
assert_contains "$out" "already matches" \
    "G4: reports that the crontab already matches"
assert_file_not_exists "$T/calls" "G4: crontab was not replaced"

# --- G5: crontab differs, answer no ---------------------------------
rm -rf "$T/env/tmp" "$T/calls"
out=$( (
    eval "$(load_fn setup_cron_jobs)"
    logging_stubs
    crontab_stub_b
    prompt_yn() { return 1; }
    ENV_DIR="$T/env"
    setup_cron_jobs
) 2>&1 ); rc=$?
assert_exit_code 0 "$rc" "G5: exits 0 when the replacement is declined"
assert_contains "$out" "left unchanged" \
    "G5: reports that the crontab was left unchanged"
assert_contains "$out" "--- installed crontab" \
    "G5: shows which is which before asking"
assert_file_not_exists "$T/calls" "G5: crontab was not replaced"
assert_equals 0 "$(find "$T/env/tmp" -type f 2>/dev/null | wc -l)" \
    "G5: no backup written when declining"

# --- G6: crontab differs, answer yes --------------------------------
rm -rf "$T/env/tmp" "$T/calls"
out=$( (
    eval "$(load_fn setup_cron_jobs)"
    logging_stubs
    crontab_stub_b
    prompt_yn() { return 0; }
    ENV_DIR="$T/env"
    setup_cron_jobs
) 2>&1 ); rc=$?
assert_exit_code 0 "$rc" "G6: exits 0 when the replacement is accepted"
assert_equals "REPLACE $T/env/config/crontab" \
    "$(cat "$T/calls")" "G6: the tracked crontab was installed"
assert_equals 1 "$(find "$T/env/tmp" -name 'crontab.backup.*' | wc -l)" \
    "G6: exactly one backup written"
backup=$(find "$T/env/tmp" -name 'crontab.backup.*' | head -1)
assert_equals "B" "$(cat "$backup")" \
    "G6: backup holds the previous crontab"

# --- G7: crontab differs, no terminal -------------------------------
rm -rf "$T/env/tmp" "$T/calls"
cat > "$T/g7.sh" <<EOF
$(load_fn setup_cron_jobs)
$(load_fn prompt_yn)
$(load_fn can_ask)
info() { printf '%s\n' "\$*"; }
warning() { printf '%s\n' "\$*"; }
debug() { printf '%s\n' "\$*"; }
log_debug() { printf '%s\n' "\$*"; }
crontab() {
    if [[ "\$1" == "-l" ]]; then
        printf '%s\n' "B"
    else
        echo "REPLACE \$*" >> "$T/calls"
    fi
}
ENV_DIR="$T/env"
setup_cron_jobs
EOF
if command -v setsid >/dev/null 2>&1; then
    out=$(setsid -w bash "$T/g7.sh" </dev/null 2>&1); rc=$?
    assert_exit_code 0 "$rc" "G7: no-terminal run exits 0"
    assert_file_not_exists "$T/calls" \
        "G7: unattended run never replaces the crontab"
else
    echo "G7: setsid is unavailable - scenario reported, not run"
fi

# --- G8: no config/crontab ------------------------------------------
mkdir -p "$T/env2"
rm -f "$T/calls"
out=$( (
    eval "$(load_fn setup_cron_jobs)"
    logging_stubs
    crontab_stub_a
    ENV_DIR="$T/env2"
    setup_cron_jobs
) 2>&1 ); rc=$?
assert_exit_code 0 "$rc" "G8: exits 0 when no tracked crontab exists"
assert_file_exists "$T/env2/config/crontab" \
    "G8: the default crontab was created"
assert_contains "$(cat "$T/env2/config/crontab")" "sync_env.sh --sync" \
    "G8: the generated crontab runs the sync"
assert_file_not_exists "$T/calls" "G8: nothing was installed"

# --- G9: static checks ----------------------------------------------
assert_equals 0 "$(grep -c 'ln -sf "$ENV_DIR/dotfiles/' "$SETUP")" \
    "G9: no .zshrc/.zshrc overwrite by link remains in setup.sh"
assert_equals 0 "$(grep -c 'pip3 install' "$SETUP")" \
    "G9: no pip3 install remains in setup.sh"
if grep -q '"pipx"' "$SETUP"; then
    echo -e "${GREEN}✓${NC} G9: pipx is in the apt package list"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} G9: pipx is in the apt package list"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

print_test_summary
