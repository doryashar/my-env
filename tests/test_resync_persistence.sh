#!/usr/bin/env bash
# Validates reboot-persistence of the bisync resync loop (docs/storagebox-bisync-init.md)
set -u
fail=0
check() {
  if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

check "loop script exists and is executable" '[ -x /home/yashar/storagebox-sync/resync-until-done.sh ]'
check "unit file exists" '[ -f /home/yashar/.config/systemd/user/storagebox-resync.service ]'
check "unit is enabled (starts at login/boot)" 'systemctl --user is-enabled storagebox-resync.service | grep -q enabled'
check "success criterion = committed listing file" 'grep -q "path1.lst" /home/yashar/storagebox-sync/resync-until-done.sh'
check "self-disables after success" 'grep -q "disable storagebox-resync.service" /home/yashar/storagebox-sync/resync-until-done.sh'
check "telegram ping wired" 'grep -q "telegram-send.sh" /home/yashar/storagebox-sync/resync-until-done.sh'
check "retry cadence present (sleep 300)" 'grep -q "sleep 300" /home/yashar/storagebox-sync/resync-until-done.sh'

exit $fail
