#!/usr/bin/env bash
set -u
RCLONE=/usr/local/bin/rclone
L1="/media/yashar/Backups"
L2="hetzner-sftp:"
LOG="/home/yashar/logs/storagebox-bisync.log"
LOCK="/run/user/1000/storagebox-bisync.lock"
mkdir -p "$(dirname "$LOG")"
exec 9>"$LOCK"
if ! flock -n 9; then
    echo "$(date -Is) another bisync already running, skipping" >> "$LOG"
    exit 0
fi
/home/yashar/storagebox-sync/mount-check.sh || exit 7
echo "$(date -Is) bisync start" >> "$LOG"
"$RCLONE" bisync "$L1" "$L2" \
    --conflict-resolve newer --conflict-loser num \
    --max-delete 25 --max-delete-size 10G \
    --max-transfer 200G \
    --max-lock 5m \
    --recover --resilient \
    --transfers 8 --checkers 8 --multi-thread-streams 1 \
    --retries 5 --low-level-retries 20 \
    --log-file "$LOG" --log-level INFO "$@"
rc=$?
echo "$(date -Is) bisync exit=$rc" >> "$LOG"
if [ "$rc" -eq 5 ]; then
    echo "$(date -Is) WARNING: bisync lists missing/corrupt - manual 'bisync --resync' required" >> "$LOG"
fi
if [ "$rc" -eq 0 ]; then
    ( /home/yashar/storagebox-sync/merkle-snap.sh >> /home/yashar/logs/merkle/merkle.log 2>&1 ) &
fi
exit "$rc"
