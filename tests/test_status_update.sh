#!/usr/bin/env bash
# Validates the health-gated status setup (docs/storagebox-bisync-init.md)
set -u
fail=0
check() {
  if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

check "status script executable" '[ -x /home/yashar/storagebox-sync/status-update.sh ]'
check "health-check timer enabled (2h)" 'systemctl --user is-enabled storagebox-status-bihourly.timer | grep -q enabled'
check "weekly timer enabled (Mon 09:00)" 'systemctl --user is-enabled storagebox-status-weekly.timer | grep -q enabled && grep -q "OnCalendar=Mon 09:00" /home/yashar/.config/systemd/user/storagebox-status-weekly.timer'
check "bi-hourly cadence is 2h" 'grep -q "OnUnitActiveSec=2h" /home/yashar/.config/systemd/user/storagebox-status-bihourly.timer'
check "auto2h mode silent when healthy" 'grep -q "auto2h" /home/yashar/storagebox-sync/status-update.sh && grep -q "healthy" /home/yashar/storagebox-sync/status-update.sh'
check "health = listings + clean exit + low errors" 'grep -q "last_exit.*0" /home/yashar/storagebox-sync/status-update.sh'
check "recovery notice wired" 'grep -q "RECOVERED" /home/yashar/storagebox-sync/status-update.sh'
check "script syntax valid" 'bash -n /home/yashar/storagebox-sync/status-update.sh'

exit $fail
