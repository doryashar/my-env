# Monitor Switch — EDID-Resilient Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `monitor-switch` resolve a monitor even when its EDID vendor reads as `unknown` (e.g. after a DP→HDMI cable swap), by adding a resolution-hint fallback, with the matching logic unit-tested.

**Architecture:** Relocate the Python helper into the repo (`scripts/tools/monitor_switch_gnome.py`, underscore name so it is importable), keep `~/.local/bin/monitor-switch-gnome.py` as a symlink to it. Extract a pure `resolve_vendors()` function (no DBus) that matches EDID-first, then falls back to a declared native resolution. Declare per-vendor resolutions in `bin/monitor-switch` and pass `vid=WxH` tokens to `resolve`. Unit-test the pure function with pytest; wire into the shell test runner.

**Tech Stack:** Python 3, pytest 9.0.2, Bash, GNOME Mutter DisplayConfig DBus API.

**Spec:** `docs/2026-08-03-monitor-switch-edid-fallback-design.md`

**Commit policy note:** Per repo policy, commits require explicit user OK. The commit steps below are staged but should be run only once the user confirms (per-task or batched at the end).

---

## File Structure

- **Create** `scripts/tools/monitor_switch_gnome.py` — relocated helper (underscore name = importable), hardened with pure resolver functions.
- **Create** `tests/test_monitor_switch_gnome.py` — pytest unit tests for the pure resolver (no DBus).
- **Create** `tests/test_monitor_switch.sh` — shell wrapper so `run_all_tests.sh` can run the pytest suite.
- **Modify** `bin/monitor-switch` — add `MONITOR_RESOLUTIONS`; build `vid=WxH` resolve args.
- **Modify** `tests/run_all_tests.sh` — register the `monitor_switch` suite.
- **Symlink** `~/.local/bin/monitor-switch-gnome.py` → `scripts/tools/monitor_switch_gnome.py`.

---

## Task 1: Relocate helper into repo + symlink (no behavior change)

**Files:**
- Create: `scripts/tools/monitor_switch_gnome.py` (copy of current `~/.local/bin/monitor-switch-gnome.py`)
- Symlink: `~/.local/bin/monitor-switch-gnome.py` → repo file

- [ ] **Step 1: Copy the helper into the repo (rename to underscores so it is importable)**

```bash
cp "$HOME/.local/bin/monitor-switch-gnome.py" /home/yashar/env/scripts/tools/monitor_switch_gnome.py
chmod +x /home/yashar/env/scripts/tools/monitor_switch_gnome.py
```

- [ ] **Step 2: Replace the old path with a symlink to the repo file**

```bash
rm "$HOME/.local/bin/monitor-switch-gnome.py"
ln -s /home/yashar/env/scripts/tools/monitor_switch_gnome.py "$HOME/.local/bin/monitor-switch-gnome.py"
```

- [ ] **Step 3: Verify the symlink and that the live tool still works (no behavior change)**

```bash
ls -l "$HOME/.local/bin/monitor-switch-gnome.py"   # expect: -> /home/yashar/env/scripts/tools/monitor_switch_gnome.py
/home/yashar/env/bin/monitor-switch list >/dev/null && echo "list OK"
```
Expected: symlink target is the repo file; `list OK` printed.

- [ ] **Step 4: Commit**

```bash
git -C /home/yashar/env add scripts/tools/monitor_switch_gnome.py
git -C /home/yashar/env commit -m "refactor(monitor-switch): relocate gnome helper into repo (symlinked from ~/.local/bin)"
```

---

## Task 2: TDD pure resolver `resolve_vendors` (RED → GREEN)

**Files:**
- Create: `tests/test_monitor_switch_gnome.py`
- Modify: `scripts/tools/monitor_switch_gnome.py` (add pure functions)

- [ ] **Step 1: Write the failing tests**

Create `tests/test_monitor_switch_gnome.py`:

```python
#!/usr/bin/env python3
"""Unit tests for monitor_switch_gnome resolver (no DBus/GNOME required)."""
import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "scripts", "tools")
)

from monitor_switch_gnome import resolve_vendors  # noqa: E402


def _mon(connector, vendor, w, h):
    """Build a monitor tuple shaped like GetCurrentState.unpack() entries:
    monitor[0] = (connector, vendor, product, serial); monitor[1] = modes
    where modes[0] = (mode_id, width, height, refresh)."""
    return (
        (connector, vendor, "product", "serial"),
        [("mode-id", w, h, 60.0)],
        {},
    )


def test_resolution_hint_fallback_when_edid_unknown():
    monitors = [
        _mon("DVI-I-2-1", "HWP", 1920, 1200),
        _mon("DVI-I-3-2", "DEL", 1920, 1200),
        _mon("HDMI-2", "unknown", 5120, 1440),
    ]
    specs = [("HWP", None), ("DEL", None), ("LEN", "5120x1440")]
    assert resolve_vendors(monitors, specs) == [
        ("HWP", "DVI-I-2-1", 1920),
        ("DEL", "DVI-I-3-2", 1920),
        ("LEN", "HDMI-2", 5120),
    ]


def test_edid_match_still_works():
    monitors = [_mon("DP-1", "HWP", 1920, 1200)]
    assert resolve_vendors(monitors, [("HWP", None)]) == [("HWP", "DP-1", 1920)]


def test_no_match_when_resolution_absent():
    monitors = [_mon("DP-1", "DEL", 1920, 1200)]
    assert resolve_vendors(monitors, [("LEN", "5120x1440")]) == []


def test_resolution_hint_cannot_steal_edid_claimed_monitor():
    monitors = [_mon("DP-1", "HWP", 5120, 1440)]
    specs = [("HWP", "5120x1440"), ("LEN", "5120x1440")]
    result = resolve_vendors(monitors, specs)
    assert ("HWP", "DP-1", 5120) in result
    assert not any(vid == "LEN" for vid, _, _ in result)


def test_width_defaults_when_no_modes():
    monitors = [(("DP-1", "HWP", "p", "s"), [], {})]
    assert resolve_vendors(monitors, [("HWP", None)]) == [("HWP", "DP-1", 1920)]
```

- [ ] **Step 2: Run tests to verify they fail (RED)**

```bash
pytest tests/test_monitor_switch_gnome.py -q
```
Expected: FAIL — `ImportError: cannot import name 'resolve_vendors'` (function does not exist yet).

- [ ] **Step 3: Implement the pure resolver functions**

In `scripts/tools/monitor_switch_gnome.py`, add these module-level functions immediately after the imports (before `class MonitorSwitcher`):

```python
def _monitor_resolution(monitor):
    """Return (width, height) from a monitor's representative mode, else None."""
    modes = monitor[1]
    if not modes:
        return None
    mode = modes[0]
    try:
        return (int(mode[1]), int(mode[2]))
    except (IndexError, ValueError, TypeError):
        return None


def _match_by_edid(monitors, vid, claimed):
    """First unclaimed monitor whose EDID vendor startswith vid.

    Returns (connector, width) or (None, None).
    """
    vid_u = vid.upper()
    for monitor in monitors:
        connector = monitor[0][0]
        if connector in claimed:
            continue
        vendor = monitor[0][1] or ""
        if vendor.upper().startswith(vid_u):
            res = _monitor_resolution(monitor)
            return connector, (res[0] if res else 1920)
    return None, None


def _match_by_resolution(monitors, expected_res, claimed):
    """First unclaimed monitor whose mode resolution equals expected_res.

    expected_res is "WxH" (e.g. "5120x1440"). Returns (connector, width)
    or (None, None).
    """
    try:
        ew_s, eh_s = str(expected_res).lower().split("x", 1)
        expected = (int(ew_s), int(eh_s))
    except (ValueError, AttributeError):
        return None, None
    for monitor in monitors:
        connector = monitor[0][0]
        if connector in claimed:
            continue
        res = _monitor_resolution(monitor)
        if res is not None and res == expected:
            return connector, res[0]
    return None, None


def resolve_vendors(monitors, vendor_specs):
    """Resolve vendor IDs to (vid, connector, width).

    EDID vendor match is primary; expected_resolution is a fallback used only
    when no EDID match is found (e.g. EDID reads as "unknown"). Each monitor
    is claimed at most once.

    Args:
        monitors: parsed monitor list from GetCurrentState.unpack().
        vendor_specs: list of (vid, expected_resolution_or_None), where
            expected_resolution is "WxH" or None.

    Returns:
        list of (vid, connector, width) in declaration order.
    """
    claimed = set()
    results = []
    for vid, expected_res in vendor_specs:
        connector, width = _match_by_edid(monitors, vid, claimed)
        if connector is None and expected_res:
            connector, width = _match_by_resolution(
                monitors, expected_res, claimed
            )
        if connector is not None:
            claimed.add(connector)
            results.append((vid, connector, width))
    return results
```

- [ ] **Step 4: Run tests to verify they pass (GREEN)**

```bash
pytest tests/test_monitor_switch_gnome.py -q
```
Expected: PASS — 5 passed.

- [ ] **Step 5: Commit**

```bash
git -C /home/yashar/env add tests/test_monitor_switch_gnome.py scripts/tools/monitor_switch_gnome.py
git -C /home/yashar/env commit -m "feat(monitor-switch): add resolve_vendors with EDID + resolution-hint fallback"
```

---

## Task 3: TDD `parse_resolve_args` (RED → GREEN)

**Files:**
- Modify: `tests/test_monitor_switch_gnome.py` (append tests)
- Modify: `scripts/tools/monitor_switch_gnome.py` (add `parse_resolve_args`)

- [ ] **Step 1: Append the failing tests**

Append to `tests/test_monitor_switch_gnome.py`:

```python
from monitor_switch_gnome import parse_resolve_args  # noqa: E402


def test_parse_resolve_args_with_resolution():
    assert parse_resolve_args(["HWP=1920x1200", "LEN=5120x1440"]) == [
        ("HWP", "1920x1200"),
        ("LEN", "5120x1440"),
    ]


def test_parse_resolve_args_bare_vid():
    assert parse_resolve_args(["HWP", "DEL"]) == [
        ("HWP", None),
        ("DEL", None),
    ]


def test_parse_resolve_args_empty_resolution_means_none():
    assert parse_resolve_args(["HWP="]) == [("HWP", None)]
```

- [ ] **Step 2: Run tests to verify the new ones fail (RED)**

```bash
pytest tests/test_monitor_switch_gnome.py -q
```
Expected: FAIL — `ImportError: cannot import name 'parse_resolve_args'`.

- [ ] **Step 3: Implement `parse_resolve_args`**

Add to `scripts/tools/monitor_switch_gnome.py` (module-level, next to the other pure functions):

```python
def parse_resolve_args(tokens):
    """Parse resolve CLI tokens into (vid, expected_resolution_or_None).

    Accepts both 'VID' (EDID-only) and 'VID=WxH' (with resolution hint).
    An empty resolution ('VID=') is treated as None (EDID-only).
    """
    specs = []
    for token in tokens:
        if "=" in token:
            vid, res = token.split("=", 1)
            res = res.strip()
            specs.append((vid, res or None))
        else:
            specs.append((token, None))
    return specs
```

- [ ] **Step 4: Run tests to verify they pass (GREEN)**

```bash
pytest tests/test_monitor_switch_gnome.py -q
```
Expected: PASS — 8 passed.

- [ ] **Step 5: Commit**

```bash
git -C /home/yashar/env add tests/test_monitor_switch_gnome.py scripts/tools/monitor_switch_gnome.py
git -C /home/yashar/env commit -m "feat(monitor-switch): add parse_resolve_args for vid=WxH tokens"
```

---

## Task 4: Wire the resolver into the helper's `resolve` command

**Files:**
- Modify: `scripts/tools/monitor_switch_gnome.py` (`resolve_monitors` method ~lines 108-128; `main()` resolve branch ~lines 280-282)

- [ ] **Step 1: Replace `MonitorSwitcher.resolve_monitors` to use the pure function**

Replace the existing `resolve_monitors` method body with:

```python
    def resolve_monitors(self, vendor_specs):
        """Resolve vendor specs to connector names with widths.

        vendor_specs: list of (vid, expected_resolution_or_None). Prints
        'vid connector width' per resolved vendor. EDID vendor match is
        primary; expected_resolution is a fallback when EDID is unknown.
        """
        serial, monitors, logical_monitors, properties = self.get_current_state()
        for vid, connector, width in resolve_vendors(monitors, vendor_specs):
            print(f"{vid} {connector} {width}")
```

- [ ] **Step 2: Update the `resolve` CLI branch in `main()` to parse tokens**

Replace the existing `elif command == "resolve" ...` branch with:

```python
    elif command == "resolve" and len(sys.argv) >= 3:
        switcher.resolve_monitors(parse_resolve_args(sys.argv[2:]))
```

- [ ] **Step 3: Verify end-to-end against the live GNOME session**

```bash
/home/yashar/env/scripts/tools/monitor_switch_gnome.py resolve HWP=1920x1200 DEL=1920x1200 LEN=5120x1440
```
Expected (with the Lenovo on HDMI in the EDID-failed state): output includes a line `LEN HDMI-2 5120`. (If the cable has since been fixed, `LEN` resolves via EDID to whatever its connector is — either way it resolves rather than being empty.)

- [ ] **Step 4: Commit**

```bash
git -C /home/yashar/env add scripts/tools/monitor_switch_gnome.py
git -C /home/yashar/env commit -m "feat(monitor-switch): wire resolve_vendors into resolve command with vid=WxH parsing"
```

---

## Task 5: Declare resolutions in the bash orchestrator

**Files:**
- Modify: `bin/monitor-switch` (add `MONITOR_RESOLUTIONS`; update `resolve_all_monitors`)

- [ ] **Step 1: Add the `MONITOR_RESOLUTIONS` declaration**

In `bin/monitor-switch`, immediately after the `MONITOR_VENDORS` declaration (around line 21), add:

```bash
# Declared native resolutions (WxH). Used as a fallback identity when a
# monitor's EDID vendor reads as "unknown" (e.g. after a DP -> HDMI swap).
declare -A MONITOR_RESOLUTIONS=(
    ["HWP"]="1920x1200"
    ["DEL"]="1920x1200"
    ["LEN"]="5120x1440"
)
```

- [ ] **Step 2: Build `vid=WxH` tokens in `resolve_all_monitors`**

Replace the body of `resolve_all_monitors()` (around lines 28-36) with:

```bash
resolve_all_monitors() {
    local output
    local args=()
    for vid in "${MONITOR_VENDORS[@]}"; do
        args+=("${vid}=${MONITOR_RESOLUTIONS[$vid]:-}")
    done
    output=$("$PYTHON_HELPER" resolve "${args[@]}")
    while IFS=' ' read -r vid conn width; do
        [ -z "$vid" ] && continue
        CONNECTOR_MAP["$vid"]="$conn"
        WIDTH_MAP["$vid"]="$width"
    done <<< "$output"
}
```

- [ ] **Step 3: Verify `monitor-switch list` now resolves all three vendors**

```bash
/home/yashar/env/bin/monitor-switch list
```
Expected: the "Resolved monitors" block shows `LEN -> <connector> (5120px)` (previously `LEN ->  (1920px)` with an empty connector).

- [ ] **Step 4: Commit**

```bash
git -C /home/yashar/env add bin/monitor-switch
git -C /home/yashar/env commit -m "feat(monitor-switch): declare native resolutions and pass vid=WxH to resolver"
```

---

## Task 6: Wire the pytest suite into the shell test runner

**Files:**
- Create: `tests/test_monitor_switch.sh`
- Modify: `tests/run_all_tests.sh` (register the `monitor_switch` suite)

- [ ] **Step 1: Create the shell wrapper**

Create `tests/test_monitor_switch.sh`:

```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pytest "$SCRIPT_DIR/test_monitor_switch_gnome.py" -q
```

```bash
chmod +x /home/yashar/env/tests/test_monitor_switch.sh
```

- [ ] **Step 2: Register the suite in `run_all_tests.sh`**

Make these four edits in `tests/run_all_tests.sh`:

(a) Help text — after the `dead_scripts_removed` line (around line 52), add:
```bash
echo "  monitor_switch          Test monitor-switch resolver (pytest)"
```

(b) Keyword list in the argument parser `case` (around line 97) — add `monitor_switch|` to the pipe-separated list so the line becomes:
```bash
        setup|env_loading|full_setup|idempotency|smoke|sync_dotfiles|tmux_config|zerotier|oref_alert_monitor|p0_fixes|security_fixes|runner_wiring|dead_scripts_removed|monitor_switch|docker|all)
```

(c) Flags + dispatch — after `run_dead_scripts_removed=0` (around line 179) add `run_monitor_switch=0`; in the `all)` case (around line 199) add `run_monitor_switch=1`; in the per-suite `case` (around line 214) add:
```bash
        monitor_switch)        run_monitor_switch=1 ;;
```

(d) Run block — after the `dead_scripts_removed` run block (around line 296), add:
```bash
if [[ $run_monitor_switch -eq 1 ]]; then
    suite_counter=$((suite_counter + 1))
    run_test_suite "Monitor Switch" "$SCRIPT_DIR/test_monitor_switch.sh" "$suite_counter"
fi
```

- [ ] **Step 3: Verify the suite runs via the runner**

```bash
bash /home/yashar/env/tests/run_all_tests.sh monitor_switch
```
Expected: `✓ Test suite 'Monitor Switch' PASSED`.

- [ ] **Step 4: Commit**

```bash
git -C /home/yashar/env add tests/test_monitor_switch.sh tests/run_all_tests.sh
git -C /home/yashar/env commit -m "test(monitor-switch): wire pytest resolver suite into run_all_tests.sh"
```

---

## Task 7: Full regression + live toggle verification

**Files:** none (verification only)

- [ ] **Step 1: Run the entire test suite to confirm no regressions**

```bash
bash /home/yashar/env/tests/run_all_tests.sh
```
Expected: `All test suites PASSED` (including the new Monitor Switch suite).

- [ ] **Step 2: Confirm the shortcut's end-to-end behavior**

```bash
/home/yashar/env/bin/monitor-switch list     # LEN resolves to a real connector
/home/yashar/env/bin/monitor-switch toggle   # actually switches to Profile 2 (LEN)
```
Expected: `list` shows `LEN -> <connector>` populated; `toggle` switches the active display profile to the Lenovo.

- [ ] **Step 3: Final commit (if any verification-only fixups were needed)**

Only if Steps 1-2 required changes:
```bash
git -C /home/yashar/env add -A
git -C /home/yashar/env commit -m "chore(monitor-switch): verification fixups"
```

---

## Known Limitations (accepted, out of scope)

- If two monitors ever share a resolution and both lose EDID, the resolution hint is ambiguous (first match wins). Documented; not handled (YAGNI).
- The physical HDMI/EDID link itself is not fixed here — this is the software resilience layer. A bad cable should still be replaced.
