# StorageBox bisync — failure root cause & fix

**Date:** 2026-09-30
**Symptom:** every scheduled `storagebox-bisync` run failed with exit 7; the
two-way sync HDD ↔ Hetzner Storage Box never completed a real run.

## Root causes

1. **Pair never initialized.** `~/.cache/rclone/bisync/` contained only the
   Sep 25 test-pair listings — no `.lst` files for the real
   `/media/yashar/Backups ↔ hetzner-sftp:` pair. Without one successful
   `--resync`, every regular run aborts: "cannot find prior Path1 or Path2
   listings… Must run --resync" (exit 7).
2. **mount-check hardcoded `/dev/sda`.** Replugging the HDD re-enumerates it
   (seen as `/dev/sdb` at 18:10) → false MOUNT-LOST → exit 7 before rclone ran.
3. Latent bug: `fail()` in mount-check.sh exited `${3:-1}` instead of `${2:-1}`
   — "wrong source" (2) was never actually returned. Found by
   `tests/test_mount_check.sh`.

## Fixes applied

- `storagebox-sync/mount-check.sh`: matches filesystem **UUID**
  (`428E297D01064BA5`) instead of device name; fixed fail() exit code.
- `storagebox-sync/bisync-run.sh`: forwards `"$@"` to rclone so override
  flags can be passed (later flags win in rclone).
- One-time init launched (supervised, flock-safe vs the 2h timer):

```bash
systemd-run --user --unit=storagebox-bisync-resync \
  /home/yashar/storagebox-sync/bisync-run.sh --resync --max-transfer 2T
```

Note: rclone v1.75 bisync `--resync` = `--resync-mode path1` and is a
**merge**: remote-only files are copied down, local-only uploaded, conflicts
won by the local HDD. Delete guards (25 files / 10G) unchanged.

## Monitoring

```bash
systemctl --user status storagebox-bisync-resync   # init run
tail -f ~/logs/storagebox-bisync.log
```

Expect hours (local 2.5T vs box 783G; up to ~1.7T upload, 2T cap).
Scheduled timer runs flock-skip while it's active. After a successful
init, regular runs create/keep the `.lst` listings and exit 0.

## Tests

- `tests/test_mount_check.sh` — 5/5 PASS (healthy=0, missing=1,
  wrong-UUID=2, no device hardcode, marker cleanup).

## Reboot persistence (2026-10-13)

- `~/.config/systemd/user/storagebox-resync.service` (enabled,
  `WantedBy=default.target`): runs `storagebox-sync/resync-until-done.sh`,
  which keeps retrying `--resync` every 5 min until the pair's `path1.lst`
  commits, survives reboots, pings Telegram on success (and on failure,
  rate-limited to 1/hour), then **disables itself** — the regular 2h timer
  takes over. Safe alongside other runs via the flock in `bisync-run.sh`.
- The old `/tmp` watcher and transient `systemd-run` units are obsolete.
- Test: `tests/test_resync_persistence.sh` (7/7 PASS).
- Oct 3 resync failure cause: 5× "SetModTime failed: file does not exist"
  on remote dirs — both sides verified healthy in isolation afterwards;
  treated as transient. The retry loop absorbs any recurrence.

## Status updates (rev 1, 2026-10-13 — superseded by rev 2 below)

- Bi-hourly until first alignment, then self-disabled; weekly Mon 09:00.
  Concurrency per user: 8 parallel data streams (was 25 SSH conns).

## Status updates (rev 2, 2026-10-16 — health-gated)

- `storagebox-status-bihourly.timer` (2h) → `status-update.sh auto2h`:
  **silent while healthy**; on errors (failed exit, >20 recent ERRORs, or
  missing listings) sends bi-hourly ❌ until recovery, then one ✅ RECOVERED.
- `storagebox-status-weekly.timer` (Mon 09:00, persistent) → weekly summary:
  health, clean/failed run counts, files copied, walk/progress, space.
- Aligned since 2026-10-15 07:37 (first clean run; retry loop self-disabled).
- Concurrency: `--transfers 8 --checkers 8 --multi-thread-streams 1`
  (8 data streams, 8 listing workers).
- Test: `tests/test_status_update.sh` (8/8).

## 2026-10-17 incident: NTFS corruption ate local files; recovered from Box

- Oct 15 ~17:00 the HDD hit I/O corruption ("error reading source directory");
  ~9,423 files across 7 trees vanished locally (no delete involved). Every
  later sync correctly tried to mirror that loss to the Box — the
  `--max-delete-size 10G` guard blocked it, preserving the only surviving copy.
- Investigation: `comm` of `.lst-err` (Oct 15 good) vs `.lst-new` (failed pass)
  isolated the exact missing set; trees: archive/docker-old (8,408),
  lexar overflow (826), lexar Drive (70), photos/media (59), gpu-emulator (48),
  personal documents+work (11).
- Recovery (`storagebox-sync/recover-from-box.sh`, supervised unit
  `storagebox-restore`): ntfsfix + rw remount, `rclone copy` the 7 trees from
  the Box (identical files skipped), restore `.lst-err → .lst`, re-enable
  timers, start a pass. Test: `tests/test_recover_script.sh` (8/8).
- **Advisory**: ntfsfix says "Volume is corrupt. You should run chkdsk" — a
  real Windows chkdsk pass is still needed. The USB link (device renames
  sda↔sdb↔sdc, bus drops, dirty flags) is the root cause chain: move the HDD
  off the shared hub / replace cable.
- Health-check false-alarm fix: a live pass with fresh log + ≤20 errors now
  counts as healthy (stale `exit=7` no longer triggers ❌ while a 9h pass is
  mid-flight).

## Cadence + Merkle tripwire (2026-10-20)

- `storagebox-bisync.timer`: 2h → **8h** (local changes are caught instantly
  by the watcher; the timer only covers remote-side edits).
- `storagebox-sync/merkle-snap.sh [root]`: per-directory aggregate picture
  (count/bytes/max-mtime, stat-only walk). Diffs each run against the
  previous picture; alerts (🚨, exit 3) on suspicious shrink: any removed
  dir, >1000 net files lost, or >10G lost. Would have caught the 2026-10-15
  NTFS corruption same-day. Refreshes automatically after every clean
  bisync pass (hook in bisync-run.sh) + nightly timer 04:30
  (`storagebox-merkle.timer`). Snapshots in `~/logs/merkle/`.
- Known blind spot (same as rsync quick-check): content change preserving
  size+mtime is invisible without `--checksum`.
- Test: `tests/test_merkle_snap.sh` (5/5).

## Post-incident notes (2026-09-30 22:00–22:30)

- First resync attempts wrote into a **read-only mount**: the HDD replugs set
  the NTFS dirty flag → `ntfs3` mounts RO ("volume is dirty and force flag
  is not set"). Fixed via `sudo umount && sudo ntfsfix -d /dev/sda && mount`;
  verified `touch` OK. If it recurs after unplugs, rerun ntfsfix.
- A SIGKILL'd unit left an **orphan rclone** holding the flock and wedged a
  systemd --user stop-job (symptom: all `systemctl --user` calls hang).
  Recovery: kill the orphan, `reset-failed`, relaunch.
- **Telegram creds**: old token in `tg-sync-status.sh` was revoked (401).
  Working pair lives in `~/.config/ailaw-pr-review/env`
  (`bot7943280211…` / chat `6709569660`). `telegram-send.sh` now strips a
  redundant `bot` prefix (was `botbot…` → 401). `tg-sync-status.sh` updated
  to the working creds. One spurious ❌ ping was sent during the
  stop/restart gap — ignore it.
- Completion ping watcher: was `/tmp/opencode/resync-watch.sh` (session-scoped)
  — **superseded** by `storagebox-resync.service` above.


## 2026-10-20: definitive HDD rebuild (GPT)

- QEMU+Win11 attempts hit a hard wall: Windows cannot see **partitionless**
  NTFS (no volume object → no chkdsk), MBR caps at 2.2TB, and GPT structures
  would overwrite the MFT (cluster 4 = LBA 16). Approved path: full rebuild.
- `storagebox-sync/recover-hdd-rebuild.sh` (root, supervised unit
  `storagebox-rebuild`): GPT + sda1 + fresh NTFS, fstab/mount-check/test
  UUID auto-update, full restore from Box, fresh bisync --resync init,
  merkle baseline, timers resume. Old chkdsk plan obsolete (fresh NTFS).
- USB device-name churn (sda/sdb/sdc) is chronic — always match by UUID.
