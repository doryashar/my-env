# Review Fix Plan

## Classification

### Infrastructure (updated by `update_infrastructure.sh`)

- `scripts/setup.sh`
- `scripts/sync_env.sh`
- `scripts/sync_dotfiles.sh`
- `scripts/sync_encrypted.sh`
- `scripts/install_docker.sh`
- `scripts/install_fonts.sh`
- `functions/common_funcs`
- `functions/helpers`

### User-Facing (everything else)

- `config/`, `dotfiles/`, `aliases`, `env_vars`
- `functions/` (git_funcs, bw_funcs, monitors, etc.)
- `scripts/` (20+ personal scripts)
- `bin/`, `docker/`, `local/`, `local_bin/`, `tmp/`

---

## Phase 1: Infrastructure — Security (Critical)

- [x] 1. Replace `eval` with `printf -v` in `functions/common_funcs:75`
- [x] 2. Replace `eval` with `printf -v` in `scripts/setup.sh:131`
- [x] 3. Fix GitHub token leak in clone URL (`scripts/setup.sh:473`)

## Phase 2: Infrastructure — Bugs (High)

- [x] 4. Fix undefined `warn` → `warning` in `scripts/setup.sh:820`
- [x] 5. Fix undefined `success` in `scripts/setup.sh:826`
- [x] 6. Quote `$@` in `scripts/sync_dotfiles.sh:801`
- [x] 7. Quote `$ENV_DIR` in `scripts/sync_encrypted.sh:5`

## Phase 3: Infrastructure — Deduplication (Medium)

- [x] 8. Consolidate `command_exists()` into `common_funcs`
- [x] 9. Extract shared logging to `functions/logging.sh`
- [x] 10. Deduplicate `prompt()`, `get_github_token()`,
       `ensure_gh_auth()` between `setup.sh` and `common_funcs`

## Phase 4: Infrastructure — Style (Medium)

- [x] 11. Move `set -euo pipefail` to top of `scripts/setup.sh`
       *(skipped — intentionally at line 82 for pre-clone logic)*
- [x] 12. Break long lines (>80 chars) in `setup.sh`,
       `sync_dotfiles.sh`
- [x] 13. Standardize to `[[ ]]` in `sync_encrypted.sh`

## Phase 5: Test Infrastructure (Medium)

- [x] 14. Remove duplicate assertions in `tests/test_helper.sh`
       (lines 95-158 duplicate lines 15-78)
- [x] 15. Migrate 5 test files to source `test_helper.sh`:
       `env_loading_test.sh`, `full_setup_test.sh`,
       `idempotency_test.sh`, `sync_dotfiles_test.sh`,
       `zerotier_test.sh`
- [x] 16. Update `AGENTS.md` test section

## Phase 6: User-Facing — Security (Critical)

- [x] 17. Remove hardcoded camera credentials from
       `scripts/show_cam.sh:7,27`
- [x] 18. Fix password in expect heredoc
       (`scripts/send_to_synopsys.sh:77`)
- [x] 19. Fix `AGE_SECRET` leak via `/proc`
       (`scripts/sync_encrypted.sh:146,875,876`)
- [x] 20. Remove hardcoded password template
       (`scripts/sftp-fstab-setup.sh:20-22`)

## Phase 7: User-Facing — Bugs (High)

- [x] 21. Fix `$(command -v file >/dev/null)` always empty
       (`scripts/generate_image.sh:122`)
- [x] 22. Fix Python syntax in bash (`scripts/soundbar_tts.sh:95`)
- [x] 23. Fix `echo` with literal `\n` (`scripts/whoami.sh:8`)
- [x] 24. Fix dual fstab entries (`scripts/sftp-fstab-setup.sh:31-38`)

## Phase 8: User-Facing — Error Handling (Medium)

- [x] 25. Add `set -e` to `scripts/monitor_running_apps.sh`
- [x] 26. Add `set -e` + quote unquoted vars in
       `scripts/detect_focused_terminal.sh`
- [x] 27. Add shebang + `set -e` to `scripts/usage.sh`
- [x] 28. Add `set -e` to `scripts/whoami.sh`
- [x] 29. Add `set -e` to `scripts/ensure_single_instance.sh`
- [x] 30. Add `set -e` to `scripts/letmein.sh`

## Phase 9: User-Facing — Style / Cleanup (Low)

- [x] 31. Remove commented-out code in `scripts/letmein.sh`
- [x] 32. Remove commented-out code in `scripts/whoami.sh`
- [x] 33. Replace hardcoded `/home/yashar` paths in
       `scripts/test_git_*.sh` (4 files)
- [x] 34. Convert tabs to 2-space in `scripts/install_appman.sh`
- [x] 35. Use UPPER_CASE for vars in `scripts/install_fonts.sh:43-45`

## Phase 10: Documentation

- [x] 36. Document `<=` vs `=>` arrows in `config/dotfiles.conf`
- [x] 37. Create `tasks/todo.md` (this file)
- [x] 38. Update `AGENTS.md` test section
- [x] 39. Update `docs/SUGGESTIONS.md` — mark completed items

---

## Review Notes (2026-05-11)

Verified todo against current repo state — items 1–7 and 17–20 confirmed
present at the stated file:line refs.

### Plan refinements

- [x] 40. **Reword #18**: Replaced expect with `sshpass -e` + `SSHPASS` env var.
- [x] 41. **Decide #19 mitigation**: chose mktemp + chmod 600 + trap EXIT
       (`get_age_identity_file()` helper in `sync_encrypted.sh`).
- [x] 42. **Verify before deleting in #14**: confirmed true duplicates, removed.
- [x] 43. **Bootstrap-check #9**: `logging.sh` sourced by `common_funcs` only;
       `setup.sh` keeps its own copy (pre-clone). No circular sourcing.
- [ ] 44. **Resolve dirty working tree first**: tree still dirty — commit or
       stash before merging.

---

## Full Audit (2026-05-12)

All 44 items verified against current repo state.

### Confirmed items with corrections

- **#19 scope expanded**: `<(echo "$AGE_SECRET")` also at
  `sync_encrypted.sh:887-888`, not just line 146. Chose **mktemp with
  chmod 600 + trap** as mitigation (works regardless of age version).
- **#26 simplified**: `detect_focused_terminal.sh` already has properly
  quoted variables — only needs `set -e` added, no quoting fixes.
- **#33 corrected**: `test_git_remote_simple.sh` has no hardcoded
  `/home/yashar` paths. Only 4 of 5 files need fixing.

### Recommended execution order

1. **Stash dirty tree** (#44) before any changes
2. **Merge Phases 1+2** (items 1-7) — small surgical fixes
3. **Phase 3** (items 8-10) after resolving #43 (circular source risk)
4. **Phase 4** (items 11-13) — style only
5. **Phase 5** (items 14-16) — test infra
6. **Phase 6** (items 17-20) — decide #40/#41 mitigation first
7. **Phase 7** (items 21-24) — user-facing bugs
8. **Phase 8** (items 25-30) — error handling
9. **Phase 9** (items 31-35) — style/cleanup
10. **Phase 10** (items 38-39) — documentation

---

## Monitor Switch EDID Fallback (2026-08-03)

Spec: `docs/2026-08-03-monitor-switch-edid-fallback-design.md`
Plan: `docs/2026-08-03-monitor-switch-edid-fallback-plan.md`

Root cause: `monitor-switch-gnome.py` matched monitors by EDID vendor prefix;
after a DP→HDMI swap the Lenovo's EDID read as `unknown` (DDC failure), so
`LEN` resolved to an empty connector and `toggle` did nothing.

- [x] 45. Relocate helper into repo (`scripts/tools/monitor_switch_gnome.py`)
       + symlink `~/.local/bin/monitor-switch-gnome.py` (commit `1a55dad`)
- [x] 46. TDD `resolve_vendors()` — EDID primary + resolution-hint fallback
       (commit `cc07acb`)
- [x] 47. TDD `parse_resolve_args()` for `vid=WxH` tokens (commit `de39b67`)
- [x] 48. Wire `resolve_vendors` into the `resolve` command (commit `82341a8`)
- [x] 49. Declare `MONITOR_RESOLUTIONS` in `bin/monitor-switch`, pass
       `vid=WxH` to resolver (commit `32e731d`)
- [x] 50. Wire pytest suite into `tests/run_all_tests.sh` as `monitor_switch`
       (commit `2695b38`)
- [x] 51. Docs: design + plan committed (commit `c5886e8`)

### Review Notes (2026-08-03)

- Verified live: `monitor-switch list` now shows `LEN -> HDMI-2 (5120px)`
  (was `LEN -> (1920px)` with empty connector); `resolve HWP=.. DEL=.. LEN=..`
  prints `LEN HDMI-2 5120`.
- Unit tests: 8 passed (`tests/test_monitor_switch_gnome.py`), no DBus needed.
- Runner regression: `runner_wiring`, `tmux_config`, `dead_scripts_removed`,
  `monitor_switch` suites all PASS.
- **Not executed live:** `monitor-switch toggle` (would switch active displays
  off mid-session) and the heavy/disruptive suites (`setup`, `full_setup`,
  `sync_dotfiles`, `docker`). Toggle is proven indirectly via resolution output.
- **Known limitation:** if two monitors share a resolution and both lose EDID,
  the hint is ambiguous (first match wins). Accepted (YAGNI).
- **Pre-existing note:** `run_all_tests.sh` arg parser only runs the first
  named suite when multiple are passed (dedup condition blocks distinct names).
  Not introduced by this change; flagged for a future fix.
- `master` is ahead of `origin/master`; push is at owner's discretion.

---

## P1 Fixes — Code Review 2026-08-28

Full review: `docs/code_review_2026-08-28.md`. Scope: critical items +
`set -e` sweep. TDD — each fix has a failing test first in
`tests/p1_fixes_test.sh`.

### Critical fixes

- [x] 52. pingme: curl `--config` corrupts JSON containing `"` —
       deliver payload via 0600 tempfile (`data = @file`, **unquoted** —
       a quoted `@"$file"` sends an empty body), add
       `TELEGRAM_API_URL` override for testability, don't kill `set -e`
       callers on curl failure
- [x] 53. aliases: `snxx` bakes `$XSIGHT_PASSWORD` in at definition
       time — single-quote it
- [x] 54. oref_alert_monitor: daemon dies on pingme failure (line 67)
       and on `data: null` payloads (jq join on null) — guard both.
       Also found+fixed: `source ../functions/pingme` pointed at the
       nonexistent `scripts/functions/` — monitor couldn't start at
       all from `scripts/tools/` (stale path from the reorg)
- [x] 55. show_cam.sh: go2rtc config with RTSP creds written 0644 to
       /tmp and never removed — `umask 077`, `chmod 600`, cleanup
- [x] 56. letmein.sh: listener binds 0.0.0.0 by default (unauthenticated
       shell) — default to 127.0.0.1
- [x] 57. Broken test assertions that can never fail:
       test_git_push.sh (`$?` captures echo; exit 0 on failure),
       sync_dotfiles_test.sh (`test_config_parsing` parent expansion +
       `&&`-short-circuit + wrong source path; `ls | head` backup
       check), smoke_test.sh (`ENV_DIR` unbound under `set -u`;
       zsh-specific `aliases` sourced under bash kills suite)

### set -e sweep (sync_encrypted.sh / sync_dotfiles.sh)

- [x] 58. merge-file conflict detection dead (`if [[ $? -eq 0 ]]` after
       errexit-killed command) — move into `if cmd; then`
- [x] 59. `git push` / `git pull` error handlers dead — `|| { error; }`
       (also `git commit ... || warning` for empty commits)
- [x] 60. Case 4: `git stash`/`git stash pop` around a guaranteed-clean
       tree — pop fails, whole merge flow unreachable — remove pair
- [x] 61. sync_dotfiles.sh `((count++))` with count=0 kills daily sync
       on first broken symlink — `count=$((count + 1))`

### P2 pass — follow-ups (2026-08-28)

Details: `docs/code_review_2026-08-28.md` (P2 section).
Regression suite: `tests/p2_followups_test.sh` (wired as `p2_followups`).

- [x] 62. update_infrastructure.sh: scope all git ops with
       `-C "$ENV_DIR"` (could fetch/overwrite the wrong repo);
       accept `--dry-run` in any argument position
- [x] 63. ENV_DIR clobber: preserve the script-derived ENV_DIR when
       sourcing config/repo.conf in sync_env.sh, sync_encrypted.sh,
       update_infrastructure.sh (save/restore) and setup.sh
       (subshell read of PRIVATE_URL)
- [x] 64. common_funcs check_github_repo_exists: no destructive
       ensure_ssh_dir (rm'd symlinked ~/.ssh); keyscan into a temp
       UserKnownHostsFile scoped to the one git ls-remote call
- [x] 65. full_setup_test.sh: fix sandbox setup (aliases/env_vars are
       files not dirs; dotfile-preserving copies; run_all_tests.sh
       expectation; REPO_ROOT instead of $HOME/env) — suite 22/22,
       local runner now 16/16 green

### Review Notes (2026-08-28)

- Full findings + fix details: `docs/code_review_2026-08-28.md`.
- Regression suite: `tests/p1_fixes_test.sh` (wired as `p1_fixes`,
  24 assertions, 9 behavioral). All tests watched RED before fixes.
- New environment quirk documented: curl config `data = @"$file"`
  (quoted) silently sends an empty body — only unquoted `@file` works.
- `smoke_test.sh` and `full_setup_test.sh` were already failing at
  HEAD before these changes (verified in a clean `git worktree`).
  Smoke fixed in this pass (zsh-based aliases/env_vars loading);
  full_setup failures are pre-existing follow-up #7.
- Local runner: 14/15 suites PASS; `full_setup` fails pre-existing.
  Docker suite skipped locally (pre-existing `assert_success 0` /
  dead `05_prerun.sh` issues — follow-up #1).

### Follow-ups (documented, not in this pass)

- Docker suites: ~30 `assert_success 0` literal-zero assertions
- ENV_DIR clobbered by `source config/repo.conf` (4 scripts)
- sync_dotfiles capture-group + backward-wildcard features dead (M1/M2)
- `functions/common_funcs:200` destructive `~/.ssh` side effect
- Test orphan suites not wired into runner (7 files)

## sysboard (2026-09-26)

- [x] Task 1: script skeleton + CLI flag parsing
- [x] Task 2: collect_systemd
- [x] Task 3: collect_timers
- [x] Task 4: collect_docker (paused-state fix included)
- [x] Task 5: collect_cron
- [x] Task 6: collect_autostart
- [x] Task 7: report mode
- [x] Task 8: TUI core (short tab labels, empty-row guard, tty probe)
- [x] Task 9: TUI actions + help (EOF guard, %b fix)
- [x] Task 10: symlink, suite registration, docs
- Plan: docs/superpowers/plans/2026-09-26-sysboard.md
- Spec: docs/superpowers/specs/2026-09-26-sysboard-design.md
