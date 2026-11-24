# monitor-switch: hotplug restore (2026-10-15)

**Affected files:** `bin/monitor-switch`, `config/systemd-user/monitor-switch-restore.service` (new), `config/udev/99-monitor-switch-restore.rules` (new), `tests/test_monitor_switch_restore.sh` (new), `tests/run_all_tests.sh`

**Plan:** `docs/superpowers/plans/2026-10-15-monitor-switch-restore.md`

## Problem

`monitor-switch` (Win+Shift+M) had no memory of the last applied layout:

1. Every apply goes through Mutter D-Bus `ApplyMonitorsConfig` **method 1
   (temporary)** to skip GNOME's confirmation dialog, so script-applied
   layouts never land in `~/.config/monitors.xml`.
2. On monitor disconnect/reconnect GNOME therefore restores a stale/default
   layout, and the script's next toggle inferred "current profile" from
   whatever was active — one keypress could land somewhere unexpected.

## Solution

- **State file** `~/.local/state/monitor-switch/last-profile` — written after
  every successful apply (`profile1`, `profile2`, or `custom:CONN CONN...`).
  Env overrides for tests: `MONITOR_SWITCH_STATE`, `MONITOR_SWITCH_HELPER`,
  `MONITOR_SWITCH_RESTORE_WAIT`.
- **`monitor-switch restore`** — re-applies the saved state:
  polls up to `RESTORE_WAIT` (default 5 s, 0.5 s interval) for the expected
  connectors to (re)appear, then applies:
  - profiles → with the **available subset** (unplug of one monitor still
    re-asserts the rest, replug restores the full set)
  - custom sets → **all-or-nothing**
  - no expected monitors available → quiet no-op (exit 0)
  - skips `ensure_keybinding` (safe from udev/systemd context, no gsettings)
- **Hotplug wiring** — udev rule on DRM `change|add` starts a systemd user
  oneshot `monitor-switch-restore.service` running `monitor-switch restore`.
  If the session isn't up (boot-time events), `systemctl --user -M` simply
  fails and udev ignores it. Service re-starts are idempotent; event bursts
  are absorbed by the poll loop.

## Restore matrix

| Saved state | Hotplug event | Result |
|---|---|---|
| profile1 (HP+DEL) | DEL replugged | HP+DEL re-applied |
| profile1 (HP+DEL) | DEL unplugged | HP-only subset re-applied |
| profile2 (LEN) | LEN replugged | LEN re-applied |
| profile2 (LEN) | LEN absent | nothing (exit 0) |
| custom:… | all present | re-applied verbatim |
| custom:… | any missing | nothing (exit 0) |
| (no file) | anything | "No saved profile to restore" |

## Install (already done on this machine, re-do after reinstall)

```bash
cp config/systemd-user/monitor-switch-restore.service ~/.config/systemd/user/
systemctl --user daemon-reload
sudo cp config/udev/99-monitor-switch-restore.rules /etc/udev/rules.d/
sudo udevadm control --reload
```

## Debug

```bash
journalctl --user -u monitor-switch-restore.service   # restore runs
cat ~/.local/state/monitor-switch/last-profile        # saved state
monitor-switch list                                   # shows "Saved profile:"
sudo udevadm trigger -c change -s drm                 # simulate hotplug
```

## Tests

`tests/test_monitor_switch_restore.sh` (24 assertions): stubs the python
helper + gsettings, covers state writes on toggle/profile/enable/custom,
subset restore, all-or-nothing custom restore, no-state no-op, and
keybinding skip. Registered as `monitor_switch_restore` in
`tests/run_all_tests.sh`.
