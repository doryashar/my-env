#!/usr/bin/env bash
# Validates merkle-snap.sh tripwire behavior (docs/storagebox-bisync-init.md)
set -u
fail=0
check() {
  if [ "$2" -eq "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (got $2 want $3)"; fail=1; fi
}
SNAP=/home/yashar/storagebox-sync/merkle-snap.sh
export MERKLE_NO_TG=1
T=/tmp/opencode/merkle-test
rm -rf "$T"; mkdir -p "$T/a" "$T/b"
for i in $(seq 1 50); do echo x > "$T/a/f$i"; done
for i in $(seq 1 50); do echo y > "$T/b/g$i"; done

"$SNAP" "$T" >/dev/null 2>&1; check "baseline exits 0" $? 0
echo new > "$T/a/f51"
"$SNAP" "$T" >/dev/null 2>&1; check "normal change exits 0" $? 0

rm "$T"/b/g*                       # mass delete: 50 files -> suspicious
"$SNAP" "$T" >/dev/null 2>&1; rc=$?
[ $rc -eq 3 ] && echo "PASS: mass delete trips wire (exit 3)" || { echo "FAIL: mass delete rc=$rc"; fail=1; }

rm "$T"/a/f*
"$SNAP" "$T" >/dev/null 2>&1; check "second mass delete still trips" $? 3
"$SNAP" "$T" >/dev/null 2>&1; check "stable tree back to 0" $? 0

rm -rf "$T"
exit $fail
