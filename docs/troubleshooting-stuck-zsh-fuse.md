# Troubleshooting: Stuck zsh / frozen terminals (dead rclone FUSE mount)

Incident date: 2026-09-26

## Symptom

- New terminal tabs/windows appear to hang forever at open.
- Shells are unkillable (even `kill -9`, `timeout` cannot stop them).
- Commenting out shell rc files (`~/.zshenv`, `~/.zshrc`) does not help —
  even `zsh --no_rcs` shells get stuck.

## Root cause

The StorageBox rclone FUSE mounts (`~/mnt/hetzner-storagebox__` and
`~/mnt/hetzner-storagebox__backup`, served by docker containers
`rclone-mount-hetzner-storagebox__*`) had a wedged backend. Any process
that stats or reads a path on those mounts blocks in **uninterruptible
kernel sleep (D state)** in `request_wait_answer` waiting for a FUSE
reply that never comes.

The shell rc files were NOT the cause. The `.zshenv` (z4h) commenting was
reverted; a full z4h startup performs zero I/O on these mount paths.

## Diagnosis commands

```bash
# 1. Confirm stuck processes are in D state waiting on FUSE
ps -eo pid,stat,cmd | awk '$2 ~ /^D/'
sudo cat /proc/<pid>/stack        # shows request_wait_answer / fuse_dentry_revalidate

# 2. Find which FUSE connection has stuck requests
for c in /sys/fs/fuse/connections/*; do
  echo "$c waiting=$(cat $c/waiting)"
done

# 3. Map connection id to mount (major:minor 0:<id>)
findmnt -t fuse.rclone -no MAJ:MIN,TARGET
```

Note: never probe a suspect mount in your foreground shell — use a
backgrounded `ls` and check on it after a few seconds, or your own
shell will freeze too. `timeout` cannot kill D-state processes.

## Fix (runbook)

```bash
# 1. Abort the stuck FUSE connections (instantly wakes all frozen
#    processes with I/O errors). Use the ids found in diagnosis.
echo 1 | sudo tee /sys/fs/fuse/connections/<id>/abort

# 2. Unmount the dead mountpoints (lazy)
sudo umount -l /home/yashar/mnt/hetzner-storagebox__
sudo umount -l /home/yashar/mnt/hetzner-storagebox__backup

# 3. Restart the mount containers
docker start rclone-mount-hetzner-storagebox__ \
             rclone-mount-hetzner-storagebox__backup

# 4. Verify mounts are live again
bash tests/storagebox_mount_health_test.sh
```

Background: the containers bind-mount the host paths and run
`rclone mount ... /data` inside, which propagates the FUSE mount back to
the host path. `docker restart` fails with
`mkdir ...: file exists` while a dead mount still occupies the path, so
always abort + unmount first.

## Prevention (deployed 2026-09-26)

Three layers are in place:

1. **Fail-fast mounts** — containers were recreated by
   `scripts/tools/storagebox_mount_recreate.sh` with
   `--contimeout=10s --timeout=60s`, a Docker `HEALTHCHECK`
   (`rclone lsf` against the SMB backend every 1m), `--user 1000:1000`
   (fuse mount owned by the user), and `/dev/fuse` + `SYS_ADMIN` +
   `apparmor=unconfined`. Backend hangs now error out in bounded time
   instead of parking processes in D-state forever.
2. **Watchdog** — `scripts/tools/storagebox_mount_monitor.sh` runs every
   5 min via the `storagebox-mount-monitor.timer` systemd user unit
   (source copies in `config/systemd-user/`). It probes both mounts
   without ever blocking, and on failure sends a Telegram alert and
   self-heals (detach corpse mounts + restart containers). Set
   `RECOVER=0` in the service unit for alert-only mode.
3. **Tests** — `tests/storagebox_mount_health_test.sh` asserts mounts
   respond, healthchecks exist, and the timer is active (part of
   `tests/run_all_tests.sh`).

Gotchas baked into the scripts (do not "simplify" them away):

- `mountpoint(1)` misreports dead fuse mounts (ENOTCONN) as
  "not a mountpoint" — detect mounts via `/proc/self/mounts`.
- Docker refuses `run`/`start`/`restart` with
  `mkdir ...: file exists` while a corpse FUSE mount occupies the bind
  source — always lazy-detach (`fusermount3 -uz`) first.
- Both containers share `--cache-dir=/cache/hetzner-storagebox`; it must
  stay owned by uid 1000 (`sudo chown -R 1000:1000
  /home/yashar/mnt/rclone-cache/hetzner-storagebox`) or the vfs cache
  fails to load.
- Never probe a suspect mount in the foreground; D-state ignores
  `timeout` and `kill -9`.
