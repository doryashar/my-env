# Fix: PC failed to boot/desktop failed to start without the external USB HDD

**Date:** 2026-09-30
**Symptom:** With the 3.6T USB HDD (sda, `Backups`) unplugged, Ubuntu showed a
black screen after GDM autologin and appeared not to boot. With the drive
plugged in, everything worked.

## Root cause

Not the sync service. It was a **GPU device-node race**:

1. At boot the kernel creates `card0` (simpledrm placeholder on the firmware framebuffer).
2. When the NVIDIA driver loads, `ubuntu-drivers-common`'s udev rule
   (`/usr/lib/udev/rules.d/71-u-d-c-gpu-detection.rules`) deletes `/dev/dri/card0`.
3. If GDM's X session starts in the window where `card0` is disappearing,
   Xorg dies: `no screens found` / `failed to take device /dev/dri/card0`
   (seen in `~/.local/share/xorg/Xorg.0.log.old` and boots -4..-1 in the journal).
4. The USB HDD changes boot timing (device enumeration + 3.6T ntfs3 mount),
   shifting the race — unplugged = X loses, plugged = X wins.

Evidence: boots -4..-1 (2026-09-29 20:50–21:01, drive absent) all show
`Fatal server error: no screens found`; today's boot with the drive present
has a healthy `gnome-shell` X11 session.

## Fixes applied

1. `/etc/default/grub`: added `initcall_blacklist=sysfb_init` to
   `GRUB_CMDLINE_LINUX_DEFAULT` (+ `update-grub`). simpledrm never loads, so
   `card0` never gets deleted and the race cannot happen. (Canonical fix for
   this Ubuntu/NVIDIA race; cosmetic cost: no graphical plymouth splash.)
2. `/etc/fstab`:
   - `Backups` ntfs3 entry: added `x-systemd.device-timeout=5s` so a missing
     HDD delays boot at most 5s (was default 90s) instead of a long hang.
   - StorageBox CIFS entry: added `_netdev,nofail,x-systemd.mount-timeout=15`.
     It failed on **every** boot (DNS not up yet) and broke `remote-fs.target`;
     with `nofail` boot proceeds and your user sync services remount it later.

## Verification

- `tests/test_boot_config.sh` checks both config files.
- Real test: **reboot once with the USB HDD unplugged** — desktop must come up.

## Related services (not the cause, kept as-is)

- `~/.config/systemd/user/storagebox-{bisync,watcher,mount-monitor}.*` start
  after login and do not block boot.
- System-level `storagebox-bisync.timer` shows as enabled but its unit files
  are gone (dangling symlink, harmless). Clean up with
  `sudo systemctl disable storagebox-bisync.timer` if desired.
