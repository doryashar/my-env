#!/usr/bin/env bash
# Validates mount-check.sh UUID-based matching (docs/storagebox-bisync-init.md)
set -u
SCRIPT=/home/yashar/storagebox-sync/mount-check.sh
fail=0
mkdir -p /tmp/opencode/test-bin
printf '#!/bin/sh\nexit 0\n' > /tmp/opencode/test-bin/notify-send
chmod +x /tmp/opencode/test-bin/notify-send
export PATH="/tmp/opencode/test-bin:$PATH"

check() {
  if [ "$2" -eq "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (got $2 want $3)"; fail=1; fi
}

# 1. Real mount, correct UUID default -> 0
"$SCRIPT" >/dev/null 2>&1; check "healthy mount returns 0" $? 0
[ ! -e ~/logs/.mount-lost ] && echo "PASS: .mount-lost cleared" || { echo "FAIL: .mount-lost present"; fail=1; }

# 2. Missing path -> 1
"$SCRIPT" /nonexistent-path-xyz >/dev/null 2>&1; check "missing path returns 1" $? 1

# 3. Mounted path but wrong expected UUID -> 2 (covers sda/sdb replug case)
"$SCRIPT" /media/yashar/Backups 0000-DEADBEEF >/dev/null 2>&1; check "wrong UUID returns 2" $? 2

# 4. Static: no hardcoded device name, UUID default present
if grep -q 'EXPECTED_UUID="${2:-428E297D01064BA5}"' "$SCRIPT" && ! grep -q '/dev/sda' "$SCRIPT"; then
  echo "PASS: UUID-based matching, no device hardcode"
else
  echo "FAIL: script still hardcodes device or lacks UUID default"; fail=1
fi

# cleanup test marker
rm -f ~/logs/.mount-lost
exit $fail
