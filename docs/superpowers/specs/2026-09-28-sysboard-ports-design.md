# sysboard: Ports Section (Listening Apps) — Design

**Date:** 2026-09-28
**Status:** Approved

## Overview

Add a seventh section to `sysboard`: **Ports** — apps listening on TCP ports,
with their port, process name/PID, and bind address. Read-only except a
`x` (kill process) action with confirmation.

## Requirements

- List TCP sockets in LISTEN state (TCP only; UDP excluded).
- Show port, process name (+PID when visible), bind address.
- `x` kills the selected listener's process after a y/N confirm (SIGTERM,
  no sudo — only own processes; failures show in red on the status bar).
- Rows without a visible PID (other users'/root sockets) ignore actions.
- Integrates with TUI (tab `7:Ports`), report mode, summary line, keybind
  range, help, usage, and docs.

## Non-Goals

- UDP sockets.
- kill -9 / signal selection.
- sudo kills for root-owned sockets.
- Deduping per-interface binds (distinct binds are distinct rows).

## Data Collection

`collect_ports` runs `ss -tulpn` (iproute2, unqualified call so tests can
mock it), filters to `tcp` netid + `LISTEN` state, and emits one TSV row per
socket:

```
PORT<TAB>PROC<TAB>PID<TAB>ADDRESS
```

- Port: last colon-separated segment of `Local Address:Port` (handles
  `[::]:8080` v6 form).
- Process: first `users:(("name",pid=N,...))` capture — name and PID empty
  when ss shows none (sockets owned by other users).
- Address: bind address verbatim from ss (`0.0.0.0` all-interfaces IPv4,
  `[::]` all-interfaces IPv6, otherwise specific IP).
- Output sorted numerically by port.
- Missing `ss` or empty result → empty output → "(none)" per the existing
  error contract.

## UI

- New section appended to `SECTIONS`/`SECTION_LABELS`/`TAB_LABELS`:
  `ports` / `"Listening Ports"` / `Ports`. Tab key `7:Ports`.
- Row display: `PORT  PROC(pid)  ADDRESS` — e.g.
  `8000  tagger-serve(1234)  0.0.0.0`; empty PROC renders as `-`.
- Summary line gains `PORTS n`.
- Keybind range extends `[1-6]` → `[1-7]` (digit keys + Tab cycle).
- Colors: rows have no state field → default color (like timers/cron).

## Actions

- `x`: confirm `kill PID (proc)?` → `kill PID` (SIGTERM). Success → status
  message + refresh; failure (e.g. not owner) → red status message. Rows
  with empty PID report "no process visible for this socket" instead.
- All other action keys (`s`/`t`/`r`/`e`/`l`/`k`) report read-only.

> Note: the kill key shipped as `x` instead of the originally drafted `k` —
> `k` collides with up-arrow navigation (arrows decode to `k`/`j`).

## Testing

Mock `ss` (fixtures: TCP LISTEN rows with process, LISTEN without process,
UNCONN/UDP rows that must be filtered, v6 addresses) and override `kill` to
record invocations. Assert: TSV parse correctness, TCP-only filtering,
port sorting, kill confirm-gating + PID-less rejection, keybind/section
registration, report rendering.

## Documentation

Update `docs/sysboard.md` (section list, `7`/`x` keys) and the usage text.
