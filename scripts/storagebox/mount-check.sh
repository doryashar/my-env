#!/usr/bin/env bash
# mount-check.sh <path> <expected-uuid> — exit 0 healthy, 1 not mounted, 2 wrong source
# Match by filesystem UUID: kernel device names (sda/sdb/...) swap on replug order.
set -u
PATH_CHECK="${1:-/media/yashar/Backups}"
EXPECTED_UUID="${2:-428E297D01064BA5}"
LOG=/home/yashar/logs/mount-check.log

fail() {
    echo "$(date -Is) MOUNT-LOST: $1" | tee -a "$LOG"
    command -v notify-send >/dev/null && notify-send -u critical "storagebox sync" "MOUNT-LOST: $1" 2>/dev/null
    touch /home/yashar/logs/.mount-lost
    exit "${2:-1}"
}

[ -d "$PATH_CHECK" ] || fail "path $PATH_CHECK missing" 1
SRC=$(findmnt -no SOURCE -T "$PATH_CHECK" 2>/dev/null)
[ -n "$SRC" ] || fail "$PATH_CHECK exists but is not a mountpoint (stale dir?)" 1
UUID=$(lsblk -nr -o UUID "$SRC" 2>/dev/null)
case "$UUID" in
    "$EXPECTED_UUID") rm -f /home/yashar/logs/.mount-lost; exit 0 ;;
    *) fail "$PATH_CHECK mounted from $SRC (uuid ${UUID:-none}), expected uuid $EXPECTED_UUID" 2 ;;
esac
