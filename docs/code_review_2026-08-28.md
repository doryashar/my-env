# Code Review 2026-08-28 — Findings & P1 Fixes

Full-repo review of `scripts/`, `functions/`, `tests/` (~10k lines) by
four parallel review agents, with the top findings verified manually.
P1 scope (this pass): critical items + the `set -e` sweep. All fixes are
TDD — each has a regression test in `tests/p1_fixes_test.sh` that was
watched failing before the fix.

## Fixed in this pass

| # | File | Bug | Fix |
|---|------|-----|-----|
| 52 | `functions/pingme` | curl `--config` interprets `\"` as escapes: any message containing `"` truncated the POST body to `{` — every quoted alert failed to deliver. Also `if [[ $? -ne 0 ]]` after an errexit-exposed assignment. | Payload delivered from a 0600 tempfile via unquoted `data = @$file`; `|| rc=$?` capture; `TELEGRAM_API_URL` override for testability; errors to stderr. **NB: `data = @"$file"` (quoted) silently sends an empty body — curl 8.5.0 config semantics.** |
| 53 | `aliases:22` | `alias snxx="echo $XSIGHT_PASSWORD \| snx"` baked the plaintext password into the alias at definition time (visible via `alias snxx`). | `alias snxx='printf "%s" "$XSIGHT_PASSWORD" \| snx'` (single quotes; expansion deferred to call time). |
| 54 | `scripts/tools/oref_alert_monitor.sh` | (a) `source ../functions/pingme` resolved to the nonexistent `scripts/functions/` — monitor could not even start from its post-reorg location. (b) Unguarded `pingme` under `set -euo pipefail`: one failed notification killed the daemon. (c) `jq '.data \| join'` on `data: null` (exit 5) killed the daemon on malformed payloads. | Path → `../../functions/pingme`; `pingme "\$msg" \|\| log ...`; `(.data // [])` in all three jq consumers + the MARK filter. |
| 55 | `scripts/tools/show_cam.sh` | go2rtc config embedding RTSP credentials written world/group-readable (0644/0664) to `/tmp`, never removed. | `umask 077` + `chmod 600` after write; `rm -f "$GO2RTC_CONFIG"` in `cleanup()` and `stop_all()`. |
| 56 | `scripts/tools/letmein.sh` | Listener bound `0.0.0.0` by default — unauthenticated `zellij attach` shell on all interfaces. | Both listeners default to `127.0.0.1` (LAN exposure now requires passing the host arg explicitly). |
| 57 | `tests/` | Assertions that could never fail: `test_git_push.sh` captured echo's exit code and exited 0 on failure; `sync_dotfiles_test.sh test_config_parsing` expanded `$DEFAULT_LINK_TYPE` in the parent (always failed) with an `&&`-short-circuited assertion + wrong `common_funcs` path; backup check piped `ls \| head` (status = head's); `smoke_test.sh` used `$ENV_DIR` unguarded under `set -u` and sourced zsh-specific `aliases` under bash (`set -u` death). | Proper rc capture (`cmd \|\| rc=$?`), single-quoted child scripts, `compgen -G` glob check, `${ENV_DIR:-}`, zsh-based loading, EXIT trap for HOME restoration. |
| 58 | `scripts/sync/sync_encrypted.sh:347,357` | `git merge-file ...; if [[ $? -eq 0 ]]` — conflicts exit 1 → errexit kills the script before the check: conflict detection was dead. | `if git merge-file -p ... > "$merged_file"; then ... else conflict ...` |
| 59 | `sync_encrypted.sh:1103,1129,1194,1227` | Unguarded `git pull`/`git push` + dead `if [[ $? -ne 0 ]]` handlers under `set -e`. | `git pull \|\| { error ...; exit 1; }`, `git push \|\| { error ...; exit 1; }`; `git commit ... \|\| warning ...` tolerates nothing-to-commit. |
| 60 | `sync_encrypted.sh` Case 4 | `git stash` after `git reset --hard` stashed nothing (clean tree) → `git stash pop` failed ("No stash entries found") → the whole both-changed merge flow was unreachable. | Stash/pop pair removed; guarded pull directly. |
| 61 | `scripts/sync/sync_dotfiles.sh:782` | `((count++))` with `count=0` returns 1 → the first broken symlink in `$HOME` killed the whole daily `sync_env --sync` cron run. | `count=$((count + 1))`. |

## Verified during the pass (new discoveries)

- curl config files: **quoted** `data = "@/path"` sends no body at all;
  only the unquoted `data = @/path` form reads the file (curl 8.5.0).
- `tests/smoke_test.sh` and `tests/full_setup_test.sh` were already
  failing at HEAD before these changes (verified in a clean worktree):
  smoke died sourcing zsh `aliases` under bash; full_setup has sandbox
  dir/file confusion (see follow-ups). Both causes are pre-existing.

## Regression coverage

`tests/p1_fixes_test.sh` (wired into `tests/run_all_tests.sh` as
`p1_fixes`): 24 assertions, 9 of them behavioral —
local HTTP capture server proving byte-exact pingme payloads (with
quotes/backslashes/emoji), timeout-based daemon-survival tests for the
oref monitor (null-data and pingme-failure), extract-and-execute of the
show_cam config block asserting mode 0600, and a set -e subshell proving
`remove_all_broken_links` completes with multiple broken links.

## Follow-ups (documented, not fixed here)

1. Docker suites (`tests/docker/suites/`): ~30 `assert_success 0`
   assertions pass a literal zero; `01_setup.sh` S04 asserts a destroyed
   `$?`; `05_prerun.sh` sources the deleted `scripts/prerun.sh`;
   `full_setup_entrypoint.sh` counts failures as passes.
2. `ENV_DIR` clobber: `sync_env.sh:28`, `sync_encrypted.sh:11`,
   `update_infrastructure.sh:52`, `setup.sh:637` source
   `config/repo.conf` which overwrites the derived `ENV_DIR` with the
   hardcoded `~/env`.
3. `sync_dotfiles.sh`: capture-group mappings (M1) and quoted-glob
   backward sync (M2) match nothing — advertised features are dead.
4. `functions/common_funcs:200-212`: `check_github_repo_exists`
   rm's/renames `~/.ssh` as a side effect of a read-only check.
5. `update_infrastructure.sh`: git commands run without `-C "$ENV_DIR"`.
6. Orphan test files not wired into the runner: `test_github_token.sh`,
   `test_git_operations.sh`, `test_git_push.sh`, `test_git_remote*.sh`
   (3 variants), `tests/sync_encrypted/test_diff_preview.sh`,
   `docker_test/docker_entrypoint.sh`.
7. `full_setup_test.sh` pre-existing failures (sandbox copies `aliases`
   into a directory named `aliases`; expects stale `scripts/setup_test.sh`).
8. Medium/low items from the review agents' reports (see session logs):
   `install_fonts.sh` subshell counters, `setup.sh:881` crontab
   replacement, `bw get status` invalid subcommand, monitors http://
   API key, `virtualenv.sh` /workspace coupling, `cam_web.py` CORS `*` +
   single-threaded server + `sys.exit` in handlers, XSS in preset
   rendering, `generate_image.sh` curl-config same-as-pingme pattern
   (uses `json`/`data`? — re-check before reuse), `\!:1` csh-style
   aliases (convert to functions), `$$PROJECT_HOME` typo in `veride_`.
