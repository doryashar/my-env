# sysboard — System Dashboard TUI: Design

**Date:** 2026-09-26
**Status:** Approved

## Overview

`sysboard` is a full-screen terminal dashboard showing everything running or
scheduled on the machine: systemd services (system + user), timers, docker
containers, cron jobs, and autostart applications. It supports both an
interactive TUI (default) and a one-shot pretty report (`--report`). Actions
(start/stop/restart/enable/disable) are available in the TUI for systemd and
docker entries.

## Requirements

- Show all services, autostart apps, docker containers, timers, and cron jobs
  in one place.
- Interactive full-screen TUI with keyboard navigation and live auto-refresh.
- One-shot report mode via flag.
- Actions on systemd services/timers and docker containers; confirm before
  mutating anything.
- Zero new dependencies (bash + coreutils + tput/ANSI only).
- Graceful degradation when a data source is unavailable (e.g. no docker).

## Non-Goals

- Mouse support.
- Managing cron entries or autostart apps (read-only).
- Remote hosts, containers beyond docker, or Windows services.
- Watch/alerting features.

## Architecture

New script: `scripts/tools/sysboard.sh`, symlinked as `bin/sysboard`
(matching the `monitor-switch` pattern). Pure bash; sources
`functions/logging.sh` color conventions but is self-contained for rendering
so it also works outside the repo checkout context (it resolves `ENV_DIR` the
same way other `scripts/tools/` scripts do).

### Data Collectors

Each collector is a standalone function emitting one entry per line as TSV
(`state<TAB>name<TAB>detail...`), shared by both TUI and report mode, and
testable in isolation via command overrides (mock functions).

| Collector | Source | Output columns |
|---|---|---|
| `collect_systemd` | `systemctl [--user] list-units --type=service --all --no-legend` + `is-enabled` join | state, name, sub-state, enabled |
| `collect_timers` | `systemctl [--user] list-timers --all --no-legend` | state, unit, next-run, last-run |
| `collect_docker` | `docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'` | state, name, image, status, ports |
| `collect_cron` | `crontab -l` + readable `/etc/cron.d/*` (comments/env lines skipped) | source label, schedule, command |
| `collect_autostart` | `~/.config/autostart/*.desktop` then `/etc/xdg/autostart/*.desktop`; parse `Name=`, `Exec=`, `X-GNOME-Autostart-enabled`, `Hidden` keys | state, name, exec |

Docker summary counts running vs total for the header line.

### Sections (tabs)

1. **System services** — systemd system units
2. **User services** — systemd user units
3. **Timers** — user + system timers
4. **Docker** — all containers (any state)
5. **Cron** — user crontab + `/etc/cron.d`
6. **Autostart** — user + system `.desktop` autostart entries (system ones dimmed)

### UI Layout

Alternate screen buffer. Top to bottom:

- Tab bar: `[1:System 2:User 3:Timers 4:Docker 5:Cron 6:Autostart]`, active
  tab highlighted/inverted.
- Summary line: counts per section, e.g. `SYS 182 ▪ USR 14 ▪ TIMER 3 ▪ DKR 5/7 ▪ CRON 4 ▪ AUTO 9`.
- Entry list for the active section, single selection, selected row inverted.
- Status bar: keybind hints and transient messages (errors, action results).

### Keybinds

| Key | Action |
|---|---|
| `↑`/`↓` or `k`/`j` | move selection |
| `1`–`6`, `Tab` | switch section |
| `s` / `t` / `r` | stop / start / restart selected (systemd, docker) |
| `e` | toggle enable/disable (systemd only) |
| `l` | logs: `journalctl -u NAME [-f]` or `docker logs`, in `$PAGER` |
| `R` | refresh now |
| `?` | help overlay |
| `q` | quit |

### Refresh

Auto-refresh every 5 seconds by default, implemented with `read -s -t 5 -n 1`
so any keypress is handled immediately and timeout triggers a redraw.
`--no-auto` disables; `--refresh N` sets interval. Selection and section are
preserved across refreshes.

### Colors

green = active/running, yellow = activating, red = failed, gray =
inactive/hidden/disabled. Follows `functions/logging.sh` palette.

### Actions

- Confirmed with inline y/n prompt drawn on the status bar before mutating.
- systemd: `systemctl [start|stop|restart|enable|disable] [--user] UNIT`.
  System units run through `sudo`; the TUI leaves the alternate screen so the
  sudo password prompt is visible, then redraws.
- docker: `docker [start|stop|restart] CONTAINER`. Assumed passwordless
  (docker group), consistent with existing compose stacks in `docker/`.
- cron/autostart rows: read-only, action keys ignored.
- After an action: refresh the section and show the result on the status bar.

## CLI

```
sysboard [options]
  --report          print all sections and exit (pretty, colored)
  --section NAME    report mode: show only that section; TUI mode: start on it
                    (system|user|timers|docker|cron|autostart)
  --no-auto         disable auto-refresh (TUI)
  --refresh N       auto-refresh interval in seconds (default 5)
  -h, --help        usage
```

Non-TTY stdin without `--report` falls back to report mode with a notice.

## Error Handling

- `set -uo pipefail` but not `-e` (interactive loop must survive failed
  commands).
- Every external command guarded with `command_exists`; unavailable source
  renders as an informational line (e.g. `docker: not installed`).
- All command output captured into variables; nothing raw is dumped to the
  screen. Errors surface on the status bar.
- Failed actions (non-zero exit) reported on status bar in red; UI state
  unchanged.

## Testing

`tests/sysboard_test.sh`, registered as suite `sysboard` in
`tests/run_all_tests.sh`. Uses `tests/test_helper.sh`.

- Collectors unit-tested by overriding `systemctl`/`docker`/`crontab` with
  mock functions emitting fixture TSVs; assert parsed rows, counts, cron
  comment filtering, autostart enabled/hidden parsing.
- `--report` output (under mocks) contains all six section headers.
- Flag parsing and non-TTY fallback behavior.

Per repo rules (CLAUDE.md): tests are written alongside each collector
(TDD), docs go in `./docs`, tests in `./tests`.

## Documentation

`docs/sysboard.md`: usage, keybinds, flags, examples, mock-based testing
notes.
