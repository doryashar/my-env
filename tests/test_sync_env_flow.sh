#!/bin/bash
# Behavioural tests for scripts/sync/sync_env.sh: commit consent and
# step isolation (temp git repos only, no network; remotes are local).
#
# Covers:
#   - git_commit_changes asks before committing; declining leaves the
#     changes uncommitted
#   - ENV_AUTO_COMMIT=1 commits without asking
#   - a failing step cannot stop the other steps; last_sync is only
#     written when every step succeeded
#   - --repo/--config are rejected
#   - push works against a local bare remote
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ENV="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "Sync Env Flow Tests"
echo "========================================"
echo ""

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# Build a small copy of the tree: the script derives ENV_DIR from its
# own location, so the copy must sit at <env>/scripts/sync/.
# logging.sh is copied because common_funcs sources it on load.
git init -q --bare "$T/origin.git"
mkdir -p "$T/env/scripts/sync" "$T/env/functions" "$T/env/config"
cp "$REAL_ENV/scripts/sync/sync_env.sh" "$T/env/scripts/sync/sync_env.sh"
cp "$REAL_ENV/functions/common_funcs" "$T/env/functions/common_funcs"
cp "$REAL_ENV/functions/logging.sh" "$T/env/functions/logging.sh"
printf 'REMOTE_URL="file://%s/origin.git"\n' "$T" \
    > "$T/env/config/repo.conf"
git -C "$T/env" init -q -b master
git -C "$T/env" config user.name t
git -C "$T/env" config user.email t@t

gitq() {
    git -C "$T/env" -c user.name=t -c user.email=t@t "$@"
}
uncommitted() {
    gitq status --porcelain
}

gitq add .
gitq commit -qm "initial"

# ENV_DEBUG=1 in every subshell: logging.sh's debug() returns 1 when
# ENV_DEBUG is empty, which would abort a sourced main under set -e.
# S1: declining the commit leaves the changes uncommitted
echo hello > "$T/env/newfile"
(
    . "$T/env/scripts/sync/sync_env.sh"
    ENV_DEBUG=1
    prompt_yn() { return 1; }
    git_commit_changes
) > "$T/s1.out" 2>&1
S1_RC=$?
assert_exit_code 0 "$S1_RC" "S1: declining the commit must exit 0"
assert_not_equals "" "$(uncommitted)" "S1: changes left uncommitted"
assert_equals "1" "$(gitq log --oneline | wc -l)" "S1: no new commit"

# S2: accepting the commit commits everything
(
    . "$T/env/scripts/sync/sync_env.sh"
    ENV_DEBUG=1
    prompt_yn() { return 0; }
    git_commit_changes
) > "$T/s2.out" 2>&1
S2_RC=$?
assert_exit_code 0 "$S2_RC" "S2: accepted commit must exit 0"
assert_equals "" "$(uncommitted)" "S2: working tree clean"
assert_equals "2" "$(gitq log --oneline | wc -l)" "S2: log has 2 commits"
assert_contains "$(gitq log -1 --format=%s)" "Auto-sync dotfiles" \
    "S2: newest subject starts with Auto-sync dotfiles"
assert_equals "newfile" "$(gitq ls-files -- newfile)" \
    "S2: newfile is tracked"

# S3: nothing to commit is a no-op
(
    . "$T/env/scripts/sync/sync_env.sh"
    ENV_DEBUG=1
    git_commit_changes
) > "$T/s3.out" 2>&1
S3_RC=$?
assert_exit_code 0 "$S3_RC" "S3: nothing to commit must exit 0"
assert_equals "2" "$(gitq log --oneline | wc -l)" "S3: still 2 commits"

# S4: ENV_AUTO_COMMIT=1 commits without calling the prompt
echo other > "$T/env/other"
(
    . "$T/env/scripts/sync/sync_env.sh"
    ENV_DEBUG=1
    prompt_yn() { exit 99; }
    export ENV_AUTO_COMMIT=1
    git_commit_changes
) > "$T/s4.out" 2>&1
S4_RC=$?
assert_exit_code 0 "$S4_RC" "S4: auto commit must exit 0 (prompt uncalled)"
assert_equals "" "$(uncommitted)" "S4: working tree clean"
assert_equals "3" "$(gitq log --oneline | wc -l)" "S4: log has 3 commits"

# S5: a failing step does not stop the rest
printf '#!/bin/bash\nexit 3\n' > "$T/env/scripts/sync/sync_dotfiles.sh"
printf '#!/bin/bash\ntouch %s/encrypted_ran\n' "$T" \
    > "$T/env/scripts/sync/sync_encrypted.sh"
(
    . "$T/env/scripts/sync/sync_env.sh"
    ENV_DEBUG=1
    prompt_yn() { return 1; }
    main --pull --dotfiles_sync --encrypted_sync --push
) > "$T/s5.out" 2>&1
S5_RC=$?
assert_exit_code 1 "$S5_RC" "S5: one failing step must exit 1"
assert_file_exists "$T/encrypted_ran" "S5: encrypted step still ran"
assert_file_not_exists "$T/env/tmp/last_sync" \
    "S5: last_sync not written after a failure"
assert_contains "$(grep 'Some steps failed' "$T/s5.out")" "dotfiles" \
    "S5: failed-steps warning names dotfiles"

# S6: all steps fine
printf '#!/bin/bash\nexit 0\n' > "$T/env/scripts/sync/sync_dotfiles.sh"
(
    . "$T/env/scripts/sync/sync_env.sh"
    ENV_DEBUG=1
    prompt_yn() { return 1; }
    main --pull --dotfiles_sync --encrypted_sync --push
) > "$T/s6.out" 2>&1
S6_RC=$?
assert_exit_code 0 "$S6_RC" "S6: all steps fine must exit 0"
assert_file_exists "$T/env/tmp/last_sync" "S6: last_sync written"

# S7: unsupported option
(
    . "$T/env/scripts/sync/sync_env.sh"
    ENV_DEBUG=1
    main --repo somewhere
) > "$T/s7.out" 2>&1
S7_RC=$?
assert_exit_code 1 "$S7_RC" "S7: unsupported option must exit 1"
assert_contains "$(cat "$T/s7.out")" "no longer supported" \
    "S7: error explains the unsupported options"

# S8: pull and push work against the local bare remote
gitq push -q -u origin master
(
    . "$T/env/scripts/sync/sync_env.sh"
    ENV_DEBUG=1
    prompt_yn() { return 0; }
    DEFAULT_CONFLICT_STRATEGY=remote
    main --push
) > "$T/s8.out" 2>&1
S8_RC=$?
assert_exit_code 0 "$S8_RC" "S8: push step against local remote"
assert_equals "$(gitq rev-parse HEAD)" \
    "$(git -C "$T/origin.git" rev-parse master)" \
    "S8: remote received the newest commit"

print_test_summary
