# sysboard Ports Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 7th sysboard section ("Ports") listing TCP listening apps with port/process/bind address, plus a `k` kill-process action.

**Architecture:** Follows sysboard's existing collector pattern exactly: one new TSV collector (`collect_ports` parsing `ss -tulpn`), one section registration, one row formatter, one new action function (`sb_kill_process`). Spec: `docs/superpowers/specs/2026-09-28-sysboard-ports-design.md`.

**Tech Stack:** Bash 5, `ss` (iproute2). Tests mock `ss` and `kill` as shell functions (functions shadow builtins in bash).

---

## Critical constraints (same as sysboard build)

1. `set -uo pipefail`, NO `set -e`.
2. `ss` called unqualified (mock-friendly).
3. Main guard stays at the bottom; tests source the script.
4. New tests appended BEFORE the `# --- run tests ---` marker; invocations added to the run list (chronological order after existing tests).
5. `kill` is a builtin but bash functions take precedence over builtins — test mocks define `kill()` safely.

---

### Task 1: collect_ports collector (TDD)

**Files:**
- Modify: `scripts/tools/sysboard.sh`
- Modify: `tests/sysboard_test.sh`

- [ ] **Step 1: Write the failing tests**

Append to `tests/sysboard_test.sh` BEFORE the `# --- run tests ---` marker:

```bash
# ---- collect_ports tests ----

mock_ss() {
  ss() {
    printf 'Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port Process\n'
    printf 'tcp   LISTEN 0      511    0.0.0.0:8000       0.0.0.0:*    users:(("tagger-serve",pid=1234,fd=4))\n'
    printf 'tcp   LISTEN 0      128    [::]:22            [::]:*       users:(("sshd",pid=900,fd=3))\n'
    printf 'tcp   LISTEN 0      511    127.0.0.1:5432     0.0.0.0:*\n'
    printf 'udp   UNCONN 0      0      172.18.0.1:55783   0.0.0.0:*    users:(("stremio",pid=2772,fd=27))\n'
    printf 'tcp   ESTAB  0      0      1.2.3.4:5555        5.6.7.8:80   users:(("curl",pid=99,fd=5))\n'
  }
}

test_collect_ports() {
  mock_ss
  local out
  out=$(collect_ports)
  assert_equals "3" "$(printf '%s' "$out" | grep -c .)" "only tcp LISTEN rows (udp/estab filtered)"
  assert_contains "$out" "$(printf '22\tsshd\t900\t[::]')" "v6 listener parsed"
  assert_contains "$out" "$(printf '5432\t\t\t127.0.0.1')" "no-process row has empty proc/pid"
  assert_contains "$out" "$(printf '8000\ttagger-serve\t1234\t0.0.0.0')" "v4 listener parsed"
  assert_equals "22" "$(collect_ports | head -1 | cut -f1)" "rows sorted by port (22 first)"
}

test_collect_ports_missing_ss() {
  ss() { return 1; }
  local out
  out=$(collect_ports)
  assert_equals "" "$out" "failed ss yields no rows"
}
```

Add `test_collect_ports` and `test_collect_ports_missing_ss` to the run section (after the last existing test invocation).

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/sysboard_test.sh`
Expected: FAIL — `collect_ports: command not found`

- [ ] **Step 3: Implement collect_ports**

Add to `scripts/tools/sysboard.sh` in the `# ---- collectors ----` section, after `collect_autostart` (before the `# ---- formatting / report ----` section):

```bash
# collect_ports -> PORT<TAB>PROC<TAB>PID<TAB>ADDRESS (tcp LISTEN only, sorted by port)
collect_ports() {
  ss -tulpn 2>/dev/null \
    | awk '$1 == "tcp" && $2 == "LISTEN"' \
    | while read -r _netid _state _rq _sq local_addr _peer procfield; do
        local port addr proc pid
        port="${local_addr##*:}"
        addr="${local_addr%:*}"
        proc=""; pid=""
        if [[ "$procfield" =~ \"([^\"]+)\",pid=([0-9]+) ]]; then
          proc="${BASH_REMATCH[1]}"
          pid="${BASH_REMATCH[2]}"
        fi
        printf '%s\t%s\t%s\t%s\n' "$port" "$proc" "$pid" "$addr"
      done \
    | sort -n
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/sysboard_test.sh`
Expected: all PASS (86 + 5 = 91 assertions)

- [ ] **Step 5: Commit**

```bash
git add scripts/tools/sysboard.sh tests/sysboard_test.sh
git commit -m "feat(sysboard): ports collector parsing ss tcp listeners"
```

---

### Task 2: Section integration + kill action + docs (TDD)

**Files:**
- Modify: `scripts/tools/sysboard.sh`
- Modify: `tests/sysboard_test.sh`
- Modify: `docs/sysboard.md`

- [ ] **Step 1: Write the failing tests**

Append to `tests/sysboard_test.sh` BEFORE the `# --- run tests ---` marker:

```bash
# ---- ports section integration tests ----

test_ports_section_registered() {
  assert_equals "ports" "${SECTIONS[6]}" "ports is section 7"
  assert_equals "Listening Ports" "${SECTION_LABELS[6]}" "report label"
  assert_equals "Ports" "${TAB_LABELS[6]}" "tab label"
  assert_equals "7" "$(sb_section_index ports)" "--section ports maps to 7"
}

test_ports_report_render() {
  mock_ss
  local out
  out=$(SYSBOARD_CRON_D=/nonexistent sb_render_report)
  assert_contains "$out" "Listening Ports" "report has ports header"
  assert_contains "$out" "tagger-serve" "report lists listener process"
  assert_contains "$out" "8000" "report lists port"
}

test_ports_format_row() {
  local line
  line=$(sb_format_row ports "$(printf '8000\ttagger-serve\t1234\t0.0.0.0')")
  assert_contains "$line" "8000" "row shows port"
  assert_contains "$line" "tagger-serve(1234)" "row shows proc(pid)"
  assert_contains "$line" "0.0.0.0" "row shows address"
  line=$(sb_format_row ports "$(printf '5432\t\t\t127.0.0.1')")
  assert_contains "$line" "-" "empty proc renders as dash"
}

test_sb_kill_process() {
  SB_SECTION=7
  SB_ROWS=("8000"$'\t'"tagger-serve"$'\t'"1234"$'\t'"0.0.0.0")
  SB_SEL=0
  sb_confirm() { return 0; }
  KILL_CALLED=0
  kill() { KILL_CALLED=1; KILL_PID="$1"; return 0; }
  sb_refresh_counts() { :; }
  sb_load_section() { :; }
  SB_MSG=""; SB_MSG_COLOR=""
  sb_kill_process
  assert_equals "1" "$KILL_CALLED" "kill invoked"
  assert_equals "1234" "$KILL_PID" "kill targets row pid"
  assert_contains "$SB_MSG" "exit 0" "success message"

  # declined confirm must not kill
  KILL_CALLED=0
  sb_confirm() { return 1; }
  sb_kill_process
  assert_equals "0" "$KILL_CALLED" "declined confirm skips kill"
}

test_sb_kill_process_no_pid() {
  SB_SECTION=7
  SB_ROWS=("5432"$'\t'\t$'\t'"127.0.0.1")
  SB_SEL=0
  SB_MSG=""
  sb_kill_process
  assert_contains "$SB_MSG" "no process visible" "pid-less row rejects kill"
}

test_sb_kill_process_failure_red() {
  SB_SECTION=7
  SB_ROWS=("8000"$'\t'"tagger-serve"$'\t'"1234"$'\t'"0.0.0.0")
  SB_SEL=0
  sb_confirm() { return 0; }
  kill() { return 1; }
  sb_refresh_counts() { :; }
  sb_load_section() { :; }
  SB_MSG=""; SB_MSG_COLOR=""
  sb_kill_process
  assert_equals "$RED" "$SB_MSG_COLOR" "failed kill sets red"
  assert_contains "$SB_MSG" "exit 1" "failure message"
}

test_ports_other_keys_readonly() {
  SB_SECTION=7
  SB_ROWS=("8000"$'\t'"tagger-serve"$'\t'"1234"$'\t'"0.0.0.0")
  SB_SEL=0
  SB_MSG=""
  sb_handle_action s
  assert_contains "$SB_MSG" "read-only" "stop rejected on ports"
  sb_handle_action k
  assert_not_contains_readonly_or_empty
}
```

NOTE on the last test helper: replace the final line of `test_ports_other_keys_readonly` — after `sb_handle_action k` the message must NOT say "read-only" (k is a real action; with no `sb_confirm`/`kill` stubs it would hang — so instead verify dispatch differently). Use this simpler final assertion instead:

```bash
test_ports_other_keys_readonly() {
  SB_SECTION=7
  SB_ROWS=("8000"$'\t'"tagger-serve"$'\t'"1234"$'\t'"0.0.0.0")
  SB_SEL=0
  SB_MSG=""
  sb_handle_action s
  assert_contains "$SB_MSG" "read-only" "stop rejected on ports"
  sb_handle_action e
  assert_contains "$SB_MSG" "read-only" "enable rejected on ports"
}
```

Add all test invocations (`test_ports_section_registered`, `test_ports_report_render`, `test_ports_format_row`, `test_sb_kill_process`, `test_sb_kill_process_no_pid`, `test_sb_kill_process_failure_red`, `test_ports_other_keys_readonly`) to the run section.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/sysboard_test.sh`
Expected: FAIL — `ports is section 7` fails (SECTIONS has 6 entries), `collect via sb_format_row ports` etc.

- [ ] **Step 3: Implement integration**

Six edits to `scripts/tools/sysboard.sh`:

3a. Globals (lines 21-23) — append ports to the three arrays:

```bash
SECTIONS=(system user timers docker cron autostart ports)
SECTION_LABELS=("System Services" "User Services" Timers Docker Cron Autostart "Listening Ports")
TAB_LABELS=(Sys Usr Timers Dkr Cron Auto Ports)
```

3b. `sb_format_row` — add a `ports)` branch to its case (after `autostart)`):

```bash
    ports)      printf '%-6s %-34s %s' "$a" "$([[ -n "$b" ]] && echo "$b($c)" || echo '-')" "$d" ;;
```

3c. `sb_collect_one` — add to its case (after `autostart)`):

```bash
    ports)      collect_ports ;;
```

3d. `sb_summary_line` — add PORTS count. Replace the printf with:

```bash
sb_summary_line() {
  printf '%bSYS%b %s ▪ USR %s ▪ TIMER %s ▪ DKR %s ▪ CRON %s ▪ AUTO %s ▪ PORTS %s%b' \
    "$BOLD" "$NC" "${SB_COUNTS[system]:-?}" "${SB_COUNTS[user]:-?}" \
    "${SB_COUNTS[timers]:-?}" "${SB_COUNTS[docker]:-?}" \
    "${SB_COUNTS[cron]:-?}" "${SB_COUNTS[autostart]:-?}" \
    "${SB_COUNTS[ports]:-?}" "$NC"
}
```

3e. TUI: keybind range + `k` action key. In `sb_tui`'s main loop case:
- change `[1-6])` to `[1-7])`
- change `s|t|r|e|l) sb_handle_action "$SB_KEY" ;;` to `s|t|r|e|l|k) sb_handle_action "$SB_KEY" ;;`

Also update the two status-bar hint lines and usage/help text:
- keybind bar line (~449): `1-6/tab section` → `1-7/tab section`, and append ` · k kill` to the second hint line
- `sb_usage` heredoc line (~48): `1-6/Tab` → `1-7/Tab` and mention `k kill` in the keys line
- `sb_help_overlay` box line (~595): `'  1-6 or Tab      switch section'` → `'  1-7 or Tab      switch section'`, and add a line `'  k               kill process (ports section)'` after the `l` line

3f. `sb_handle_action` — add ports dispatch. Insert a `ports)` branch before the final `*)` branch:

```bash
    ports)
      case "$1" in
        k) sb_kill_process ;;
        *) SB_MSG="read-only action" ;;
      esac
      ;;
```

And add `sb_kill_process` to the TUI actions section (after `sb_docker_action`):

```bash
sb_kill_process() {
  local port proc pid addr
  IFS=$'\t' read -r port proc pid addr <<<"${SB_ROWS[$SB_SEL]:-}"
  if [[ -z "$pid" ]]; then
    SB_MSG="no process visible for this socket"
    SB_MSG_COLOR=""
    return 1
  fi
  sb_confirm "kill $proc (pid $pid)?" || return 1
  kill "$pid"
  local rc=$?
  if [[ $rc -ne 0 ]]; then SB_MSG_COLOR="$RED"; else SB_MSG_COLOR=""; fi
  SB_MSG="kill $proc (pid $pid) -> exit $rc"
  sb_refresh_counts
  sb_load_section
}
```

- [ ] **Step 4: Update docs**

`docs/sysboard.md`:
- Section list: add `7. **Listening Ports** — \`ss -tulpn\` TCP LISTEN sockets (port, process, address)`
- Keys table: add row `| \`k\` | kill process (ports section, with confirm) |`
- Adjust the intro line mentioning sections if it enumerates them.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/sysboard_test.sh`
Expected: all PASS (91 + 16 = 107 assertions)

- [ ] **Step 6: Manual verification (read-only)**

```bash
bash bin/sysboard --report --section ports
bash bin/sysboard --help
printf '7q' | SYSBOARD_FORCE_TUI=1 TERM=xterm setsid -w bash scripts/tools/sysboard.sh --no-auto 2>&1 | head -6
```

Expected: ports report lists real listeners sorted by port; TUI opens on tab 7 (inverted `[7:Ports]`) and quits on q with exit 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/tools/sysboard.sh tests/sysboard_test.sh docs/sysboard.md
git commit -m "feat(sysboard): ports section with kill action"
```

---

## Self-Review (done during planning)

- **Spec coverage:** TCP-only filter (Task 1 awk), port/proc/pid/addr TSV (Task 1), sort by port (Task 1), tab 7 + labels (Task 2 3a), row display with `-` for empty proc (3b), summary PORTS (3d), keybind 1-7 + k (3e), kill w/ confirm + no-sudo + red failures + pid-less rejection (3f + tests), read-only other keys (3f), report render (3c + test), usage/help/docs (3e, Step 4), missing-ss → empty (Task 1 test). All covered.
- **Placeholders:** none.
- **Naming consistency:** `collect_ports`, `sb_kill_process` used consistently in tests and implementation; TSV field order `PORT/PROC/PID/ADDRESS` consistent between collector, `sb_format_row ports`, `sb_kill_process` read, and `sb_selected_unit`-style reads.
