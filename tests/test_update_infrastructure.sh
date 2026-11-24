#!/bin/bash
#
# Update Infrastructure Tests
#
# Behavioural tests for update_infrastructure.sh with local-path
# remotes (no network): "up to date" must also cover a LOCAL repo
# that is ahead, --dry-run must not touch files, an unanswered
# prompt (no terminal) must abort, --yes applies, local-only edits
# survive, files removed upstream are never deleted locally, an
# unreachable upstream fails, and no temporary file is left behind.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

SCRIPT="$SCRIPT_DIR/../scripts/sync/update_infrastructure.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# Quiet git with identity and default branch pinned
gitq() {
    git -c user.name=t -c user.email=t@t -c init.defaultBranch=master "$@" >/dev/null 2>&1
}

# The INFRA_FILES entries of the script: the quoted names between
# the lines `INFRA_FILES=(` and `)`
infra_files() {
    sed -n '/^INFRA_FILES=(/,/^)/p' "$SCRIPT" | grep -oE '"[^"]+"' | tr -d '"'
}

# Fixture: upstream repo with every infra file at v1, one commit
gitq init "$T/up"
for f in $(infra_files); do
    mkdir -p "$T/up/$(dirname "$f")"
    printf 'v1\n' > "$T/up/$f"
done
gitq -C "$T/up" add -A
gitq -C "$T/up" commit -m v1

# Local repo: clone of upstream, with the script itself and a
# repo.conf pointing at the local upstream (ENV_DIR is derived from
# the script's own location)
gitq clone "$T/up" "$T/env"
mkdir -p "$T/env/scripts/sync" "$T/env/config"
cp "$SCRIPT" "$T/env/scripts/sync/update_infrastructure.sh"
printf 'UPSTREAM_URL="%s"\n' "$T/up" > "$T/env/config/repo.conf"

# Run the script from its directory, capturing stdout+stderr and rc
run() {
    ( cd "$T/env/scripts/sync" && bash update_infrastructure.sh "$@" ) \
        > "$T/out" 2>&1
    rc=$?
    out="$(cat "$T/out")"
}

# --- U1: equal commits ----------------------------------------------
run
assert_exit_code 0 "$rc" "U1: exits 0 when equal to upstream"
assert_contains "$out" "Already up to date" \
    "U1: reports that nothing to do"

# --- U2: local ahead -----------------------------------------------
printf 'local-newer\n' > "$T/env/functions/helpers"
gitq -C "$T/env" add -A
gitq -C "$T/env" commit -m local-newer
run
assert_exit_code 0 "$rc" "U2: exits 0 when local is ahead"
assert_contains "$out" "Already up to date" \
    "U2: local-ahead is not reported as an update"
assert_equals "local-newer" "$(cat "$T/env/functions/helpers")" \
    "U2: newer local file untouched"

# --- U3: upstream ahead, dry run ------------------------------------
printf 'v2\n' > "$T/up/functions/helpers"
printf 'v2\n' > "$T/up/env_funcs"
gitq -C "$T/up" add -A
gitq -C "$T/up" commit -m v2
run --dry-run
assert_exit_code 0 "$rc" "U3: dry run exits 0"
assert_contains "$out" "functions/helpers" \
    "U3: dry run lists functions/helpers"
assert_contains "$out" "env_funcs" "U3: dry run lists env_funcs"
assert_equals "local-newer" "$(cat "$T/env/functions/helpers")" \
    "U3: dry run does not touch functions/helpers"
assert_equals "v1" "$(cat "$T/env/env_funcs")" \
    "U3: dry run does not touch env_funcs"

# --- U4: upstream ahead, nobody answers ----------------------------
out="$(setsid -w bash -c "cd '$T/env/scripts/sync' && bash update_infrastructure.sh" \
    </dev/null 2>&1)"; rc=$?
assert_exit_code 0 "$rc" "U4: no-terminal run exits 0"
assert_contains "$out" "Aborted" \
    "U4: unanswered prompt aborts instead of applying"
assert_equals "local-newer" "$(cat "$T/env/functions/helpers")" \
    "U4: functions/helpers unchanged"
assert_equals "v1" "$(cat "$T/env/env_funcs")" \
    "U4: env_funcs unchanged"

# --- U5: apply ------------------------------------------------------
run --yes
assert_exit_code 0 "$rc" "U5: apply exits 0"
assert_equals "v2" "$(cat "$T/env/functions/helpers")" \
    "U5: functions/helpers updated to upstream content"
assert_equals "v2" "$(cat "$T/env/env_funcs")" \
    "U5: env_funcs updated to upstream content"
assert_contains "$out" "Updated 2 infrastructure files" \
    "U5: reports the two updated files"

# --- U6: local-only edits survive an update -------------------------
printf 'mine\n' > "$T/env/functions/logging.sh"
printf 'v3\n' > "$T/up/functions/helpers"
gitq -C "$T/up" add -A
gitq -C "$T/up" commit -m v3
run --yes
assert_exit_code 0 "$rc" "U6: update exits 0"
assert_equals "mine" "$(cat "$T/env/functions/logging.sh")" \
    "U6: local-only edit preserved"
assert_equals "v3" "$(cat "$T/env/functions/helpers")" \
    "U6: changed file updated"

# --- U7: a file removed upstream is never deleted locally -----------
gitq -C "$T/up" rm functions/helpers
gitq -C "$T/up" commit -m remove-helpers
run --yes
assert_exit_code 0 "$rc" "U7: exits 0 when a file is removed upstream"
assert_file_exists "$T/env/functions/helpers" \
    "U7: removed-upstream file still exists locally"

# --- U8: unreachable upstream ----------------------------------------
printf 'UPSTREAM_URL="%s"\n' "$T/does-not-exist" > "$T/env/config/repo.conf"
run
assert_exit_code 1 "$rc" "U8: exits 1 when upstream is unreachable"
assert_contains "$out" "Failed to fetch" \
    "U8: reports the fetch failure"

# --- U9: no temporary file left anywhere ----------------------------
assert_equals 0 "$(find "$T" -type f -name 'tmp.*' | wc -l)" \
    "U9: no temp files left in the fixture"
stray="$(git -C "$T/env" status --porcelain \
    | awk '/^\?\? / { sub(/^\?\? /, ""); print }' \
    | grep -v '^config/' | grep -v '^scripts/sync/update_infrastructure.sh$' || true)"
assert_equals "" "$stray" \
    "U9: no stray untracked files in the env repo"
assert_equals "sync_dotfiles.sh
sync_encrypted.sh
sync_env.sh
update_infrastructure.sh" \
    "$(ls -A "$T/env/scripts/sync" | sort)" \
    "U9: scripts/sync contains exactly the expected files"

print_test_summary
