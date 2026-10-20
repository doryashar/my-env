#!/usr/bin/env bash
# Validates the recovery script (docs/storagebox-bisync-init.md, 2026-10-17 incident)
set -u
fail=0
check() {
  if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

check "script executable" '[ -x /home/yashar/storagebox-sync/recover-from-box.sh ]'
check "script syntax valid" 'bash -n /home/yashar/storagebox-sync/recover-from-box.sh'
check "covers all 7 affected trees" '[ $(grep -c "^  \"" /home/yashar/storagebox-sync/recover-from-box.sh) -eq 7 ]'
check "restores both listings" 'grep -c "lst-err" /home/yashar/storagebox-sync/recover-from-box.sh | grep -q "2" || [ $(grep -c "for side in" /home/yashar/storagebox-sync/recover-from-box.sh) -ge 1 ]'
check "re-enables both timers" 'grep -q "storagebox-bisync.timer storagebox-status-bihourly.timer" /home/yashar/storagebox-sync/recover-from-box.sh'
check "kicks a sync pass" 'grep -q "start storagebox-bisync.service" /home/yashar/storagebox-sync/recover-from-box.sh'
check "telegram completion wired" 'grep -q "Recovery restore complete" /home/yashar/storagebox-sync/recover-from-box.sh'
check "uses 8 workers" 'grep -q "transfers 8" /home/yashar/storagebox-sync/recover-from-box.sh'

exit $fail
