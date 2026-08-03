# Monitor Switch — EDID-Resilient Resolution (Resolution-Hint Fallback)

**Date:** 2026-08-03
**Status:** Approved (pending implementation)
**Owner:** yashar
**Affected files:** `bin/monitor-switch`, `scripts/tools/monitor_switch_gnome.py` (new, relocated), `tests/test_monitor_switch_gnome.py` (new), `tests/run_all_tests.sh`

## 1. Problem / Root Cause

The `Win+Shift+M` shortcut runs `bin/monitor-switch toggle`, which orchestrates
`monitor-switch-gnome.py`. The Python helper resolves declared vendor IDs
(`HWP`, `DEL`, `LEN`) to live connectors by **EDID vendor-prefix match**
(`monitor-switch-gnome.py`, `resolve_monitors()`):

```python
if vendor.upper().startswith(vid.upper()):
```

After switching the Lenovo monitor's cable from DisplayPort to HDMI, its EDID is
no longer read over the link (DDC channel failure). GNOME's
`org.gnome.Mutter.DisplayConfig` reports it as:

```
Monitor: HDMI-2
  Vendor: unknown, Product: unknown, Serial: unknown
  Current mode: 5120x1440 @ 59.98Hz
```

The DRM sysfs EDID blobs for all HDMI connectors are 0 bytes, confirming the
EDID read failure. The video stream and the preferred mode (5120x1440) are still
available — only the vendor string is missing.

**Causal chain:**

```
HDMI link fails DDC (EDID) read
  -> kernel delivers vendor="unknown" to mutter
  -> resolve_monitors(): "unknown".startswith("LEN") is False
  -> LEN resolves to an empty connector
  -> Profile 2 (LEN) has 0 available monitors
  -> toggle silently does nothing
```

The script's vendor-ID design is sound; the upstream data is missing. This
change adds a software resilience layer so the shortcut survives a missing EDID
vendor. (The physical HDMI link is a separate, out-of-scope concern.)

## 2. Goal / Non-Goals

**Goal:** Resolve a declared vendor to its connector even when the monitor's EDID
vendor is `unknown`, using the monitor's preferred-mode resolution as a fallback
identity. Make the matching logic unit-testable without a live GNOME/DBus
session.

**Non-goals:**
- Fixing the physical HDMI cable / EDID read.
- Changing profile logic, positioning model, keybinding, or the `enable` /
  `profile` commands beyond what the resolver feeds them.
- Connector-family matching or process-of-elimination (YAGNI — resolution hint
  covers the observed case).

## 3. Design Decisions (chosen)

1. **Fallback strategy: resolution hint.** Declare each vendor's expected native
   resolution; when EDID vendor match fails, match the monitor whose preferred
   mode equals the declared resolution.
2. **Code location: relocate into repo + symlink.** Move the helper into the
   repo at `scripts/tools/monitor_switch_gnome.py` (alongside `cam_*.py`) and
   make `~/.local/bin/monitor-switch-gnome.py` a symlink to it. The bash script
   reads `$HOME/.local/bin/monitor-switch-gnome.py`, so it keeps working
   unchanged. Core logic becomes versioned and unit-testable.

## 4. Architecture

### 4.1 Single source of truth = the bash config

`bin/monitor-switch` already owns profiles, vendor order, and (discovered)
widths. Add a declared resolution per vendor:

```bash
declare -A MONITOR_RESOLUTIONS=(
  ["HWP"]="1920x1200"
  ["DEL"]="1920x1200"
  ["LEN"]="5120x1440"
)
```

The `resolve` subcommand is invoked with `vid=resolution` tokens instead of bare
vendor IDs:

```
monitor-switch-gnome.py resolve HWP=1920x1200 DEL=1920x1200 LEN=5120x1440
```

Output format is unchanged: `vid connector width` per resolved vendor, one per
line. The `width` is the matched monitor's preferred-mode width (live data),
so it populates `WIDTH_MAP` exactly as today; the bash consumer is unchanged.
The declared resolution is used as the **fallback-match key** (and as an
emergency width only if a matched monitor has no mode). Net bash change is just
argument construction (`vid=res` tokens) plus the `MONITOR_RESOLUTIONS` map —
no width-handling changes.

A vendor without a declared resolution simply has no fallback (EDID-only,
current behavior) — backward compatible.

### 4.2 Pure resolver function (for testability)

Split `resolve_monitors` into:

- **`resolve_vendors(monitors, vendor_specs) -> list[(vid, connector, width)]`**
  — pure function, no DBus. `monitors` is the parsed monitor list from
  `GetCurrentState`; `vendor_specs` is `[(vid, expected_res_or_None)]`.
- A thin wrapper in `MonitorSwitcher` that fetches live state via DBus and calls
  `resolve_vendors`.

### 4.3 Matching algorithm

Maintain a set of **claimed** connectors. For each `(vid, expected_res)`:

1. **EDID match (primary):** among unclaimed monitors, find one whose `vendor`
   startswith `vid`. Claim it; width = that monitor's preferred-mode width.
   *(Normal operation unchanged.)*
2. **Resolution-hint fallback:** if no EDID match **and** `expected_res` is
   declared: among unclaimed monitors, find one whose preferred-mode resolution
   equals `expected_res` (format `WxH`, e.g. `5120x1440`). Claim it; width =
   preferred-mode width, falling back to the declared width if the mode is
   missing.
3. **No match:** emit nothing for that vendor (same as today).

**Invariants:**
- A monitor already claimed by EDID cannot be re-claimed by a resolution hint
  (no double-assignment).
- Iteration is deterministic (declaration order; first matching monitor wins if
  multiple share a resolution).

## 5. Test Plan (TDD — tests written first, pure function, no DBus)

Framework: `pytest` (9.0.2 available). Tests at
`tests/test_monitor_switch_gnome.py`.

Fixture mimics live `GetCurrentState` monitor tuples, including the **bug
scenario**: an `HDMI-2` monitor with `vendor="unknown"` and preferred mode
`5120x1440x60`.

1. **RED (the bug):** with `LEN=5120x1440` and HDMI-2's EDID vendor `unknown`,
   `resolve_vendors` returns `LEN -> HDMI-2`. (Fails on current code.)
2. **EDID regression guard:** `HWP` still resolves to its connector via EDID when
   vendor is present.
3. **No false match:** a vendor whose declared resolution matches no unclaimed
   monitor resolves to nothing (not a wrong connector).
4. **No double-assignment:** a resolution hint cannot claim a monitor that an
   EDID match already took.
5. **Width contract:** returned width comes from the matched monitor's preferred
   mode when available (covers both EDID and fallback paths).

`tests/run_all_tests.sh` gets a one-line hook to also run
`pytest tests/test_monitor_switch_gnome.py`, so the AGENTS.md entry point
(`bash tests/run_all_tests.sh`) covers it.

## 6. Files Touched

- **New** `scripts/tools/monitor_switch_gnome.py` — relocated + hardened helper.
- **New** `tests/test_monitor_switch_gnome.py` — pytest unit tests.
- **New** `docs/2026-08-03-monitor-switch-edid-fallback-design.md` — this spec.
- **Edit** `bin/monitor-switch` — add `MONITOR_RESOLUTIONS`; build `vid=res`
  resolve args; read width from declaration.
- **Edit** `tests/run_all_tests.sh` — pytest hook.
- **Symlink** `~/.local/bin/monitor-switch-gnome.py` -> repo file (replaces the
  old standalone copy).

## 7. Rollout / Verification

1. Run `pytest tests/test_monitor_switch_gnome.py` — all green.
2. Run `bash tests/run_all_tests.sh` — no regressions.
3. Live check: `bin/monitor-switch list` shows `LEN -> HDMI-2` populated and
   `Vendor:` no longer blocking the match.
4. Live check: `bin/monitor-switch toggle` actually switches to Profile 2.

## 8. Risks

- **Symlink/portability:** the relocated file keeps its shebang and exec bit; the
  symlink preserves the old path so `bin/monitor-switch` is unaffected.
- **Declared-vs-live width drift:** positioning still uses the matched
  monitor's live preferred-mode width (unchanged); the declared resolution is
  only the fallback-match key. No positioning behavior change.
- **Resolution collisions:** if two monitors ever share a resolution and both
  lose EDID, the hint is ambiguous. Accepted (YAGNI); documented as a known
  limitation, not handled.
