#!/bin/bash
#
# Shell Libs Tests
#
# Behavioural tests for the shell libraries (functions/, dotfiles/.env.zsh,
# aliases): prompts without a terminal, the bash/zsh repo-URL parse,
# error() in interactive shells, the glob option in file_chat_funcs, and
# the .env.zsh functions guard. Every check runs a child process; nothing
# is written outside T and nothing is sent anywhere.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helper.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# The tree that holds functions/, dotfiles/ and aliases. Defaults to the
# real tree; tests run against the work copies with
# SHELL_LIBS_ROOT=/path/to/work.
ROOT="${SHELL_LIBS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# T1: prompt with no terminal, under set -e
test_t1_prompt_no_terminal() {
    local out rc
    out=$(setsid -w bash -c 'set -euo pipefail; source "$1"; if prompt "q: " v; then echo "got=[$v]"; else echo noprompt; fi; echo alive' \
        _ "$ROOT/functions/common_funcs" </dev/null 2>"$T/t1.err")
    rc=$?
    assert_exit_code 0 "$rc" "T1: prompt with no terminal exits 0"
    assert_equals "$(printf 'noprompt\nalive')" "$out" \
        "T1: stdout is exactly the two lines noprompt/alive"
}

# T2: prompt_yn with no terminal, under set -e
test_t2_prompt_yn_no_terminal() {
    local out rc
    out=$(setsid -w bash -c 'set -euo pipefail; source "$1"; if prompt_yn "y/n "; then echo yes; else echo no; fi; echo alive' \
        _ "$ROOT/functions/common_funcs" </dev/null 2>"$T/t2.err")
    rc=$?
    assert_exit_code 0 "$rc" "T2: prompt_yn with no terminal exits 0"
    assert_equals "$(printf 'no\nalive')" "$out" \
        "T2: stdout is exactly the two lines no/alive"
}

# T3: with no terminal, piped stdin is left alone
test_t3_prompt_leaves_piped_stdin() {
    local out rc
    out=$(setsid -w bash -c 'source "$1"; echo answer | if prompt "q: " v; then echo "got=[$v]"; else echo noprompt; fi' \
        _ "$ROOT/functions/common_funcs" </dev/null 2>"$T/t3.err")
    rc=$?
    assert_exit_code 0 "$rc" "T3: no-terminal child exits 0"
    assert_equals "noprompt" "$out" \
        "T3: piped stdin is not consumed, prompt reports nobody"
}

# T4: parse_repo_url under bash AND under zsh, in a child each
test_t4_parse_repo_url_both_shells() {
    local sh url expected out
    for sh in bash zsh; do
        for pair in \
            "git@github.com:me/encrypted.git me/encrypted" \
            "https://github.com/me/encrypted.git me/encrypted" \
            "https://github.com/me/encrypted me/encrypted" \
            "git@gitlab.com:me/encrypted.git NOPARSE"; do
            url="${pair%% *}"
            expected="${pair#* }"
            if [[ "$sh" == zsh ]]; then
                out=$(zsh -f -c 'source "$1"; if parse_repo_url "$2"; then echo "$REPO_OWNER/$REPO_NAME"; else echo NOPARSE; fi' \
                    _ "$ROOT/functions/common_funcs" "$url" 2>/dev/null)
            else
                out=$(bash -c 'source "$1"; if parse_repo_url "$2"; then echo "$REPO_OWNER/$REPO_NAME"; else echo NOPARSE; fi' \
                    _ "$ROOT/functions/common_funcs" "$url" 2>/dev/null)
            fi
            assert_equals "$expected" "$out" \
                "T4 [$sh]: parse $url"
        done
    done
}

# T5: logging.sh error() - interactive survives, non-interactive exits
test_t5_error_interactive_vs_script() {
    local out rc has_after
    out=$(zsh -f -i -c 'source "$1"; error "boom"; echo survived' \
        _ "$ROOT/functions/logging.sh" 2>"$T/t5i.err")
    rc=$?
    assert_contains "$out" "survived" \
        "T5: in an interactive shell error does not exit"
    out=$(bash -c 'source "$1"; error "boom"; echo after' \
        _ "$ROOT/functions/logging.sh" 2>"$T/t5s.err")
    rc=$?
    assert_exit_code 1 "$rc" "T5: in a non-interactive script error exits 1"
    has_after=no
    [[ "$out" == *after* ]] && has_after=yes
    assert_equals "no" "$has_after" \
        "T5: non-interactive run prints nothing after error"
}

# T6: file_chat_funcs leaves the glob option alone
test_t6_file_chat_funcs_nomatch() {
    local out
    out=$(zsh -f -c 'source "$1" >/dev/null 2>&1; if [[ -o nomatch ]]; then echo nomatch-on; else echo nomatch-off; fi' \
        _ "$ROOT/functions/file_chat_funcs")
    assert_equals "nomatch-on" "$out" \
        "T6: nomatch option stays on after sourcing file_chat_funcs"
}

# T7: .env.zsh survives a missing functions directory
test_t7_env_zsh_missing_functions_dir() {
    local out
    mkdir -p "$T/home" "$T/env"
    echo "alias zz_probe_alias='true'" > "$T/env/aliases"
    out=$(HOME="$T/home" ENV_DIR="$T/env" zsh -f -c 'source "$1"; if alias zz_probe_alias >/dev/null 2>&1; then echo ALIAS_LOADED; else echo ALIAS_MISSING; fi' \
        _ "$ROOT/dotfiles/.env.zsh" 2>"$T/t7a.err")
    assert_contains "$out" "ALIAS_LOADED" \
        "T7: aliases load when the functions directory is missing"
    mkdir -p "$T/env/functions"
    echo 'zz_probe_func() { echo fn; }' > "$T/env/functions/zzlib"
    out=$(HOME="$T/home" ENV_DIR="$T/env" zsh -f -c 'source "$1"; if typeset -f zz_probe_func >/dev/null; then echo FN_LOADED; else echo FN_MISSING; fi' \
        _ "$ROOT/dotfiles/.env.zsh" 2>"$T/t7b.err")
    assert_contains "$out" "FN_LOADED" \
        "T7: functions load when the directory exists"
}

# T8: common_funcs is sourceable by zsh without an error message
test_t8_common_funcs_zsh_sourceable() {
    local out last has_nf
    out=$(zsh -f -c 'source "$1"; echo ZSHPROC' \
        _ "$ROOT/functions/common_funcs" 2>"$T/t8.err")
    last="${out##*$'\n'}"
    assert_equals "ZSHPROC" "$last" "T8: last stdout line is ZSHPROC"
    has_nf=no
    grep -q "not found" "$T/t8.err" 2>/dev/null && has_nf=yes
    assert_equals "no" "$has_nf" "T8: stderr does not contain not found"
}

# T9: static checks on the alias/dotfile copies
test_t9_static_alias_and_dotfile_copies() {
    local aliases_file="$ROOT/aliases" env_file="$ROOT/dotfiles/.env.zsh"
    local aliases_text env_text bad_zellij bad_emacs
    aliases_text="$(cat "$aliases_file")"
    env_text="$(cat "$env_file")"
    assert_contains "$aliases_text" \
        'alias zj="zellij -l strider attach --create dor"' \
        "T9: zj alias fixed"
    assert_contains "$aliases_text" "alias e=" "T9: e alias kept"
    bad_zellij=no
    grep -q '~/zellij' "$aliases_file" && bad_zellij=yes
    assert_equals "no" "$bad_zellij" "T9: no ~/zellij reference"
    bad_emacs=no
    grep -q '/bin/emacs' "$aliases_file" && bad_emacs=yes
    assert_equals "no" "$bad_emacs" "T9: no /bin/emacs reference"
    assert_contains "$env_text" \
        'if [[ -d "${ENV_DIR}/functions" ]]; then' \
        "T9: functions loop guarded by directory check"
}

# T10: setup.sh syntax
test_t10_setup_sh_syntax() {
    local rc=0
    bash -n "$REPO_ROOT/scripts/install/setup.sh" || rc=$?
    assert_exit_code 0 "$rc" "T10: setup.sh passes bash -n"
}

test_t1_prompt_no_terminal
test_t2_prompt_yn_no_terminal
test_t3_prompt_leaves_piped_stdin
test_t4_parse_repo_url_both_shells
test_t5_error_interactive_vs_script
test_t6_file_chat_funcs_nomatch
test_t7_env_zsh_missing_functions_dir
test_t8_common_funcs_zsh_sourceable
test_t9_static_alias_and_dotfile_copies
test_t10_setup_sh_syntax

print_test_summary
exit $?
