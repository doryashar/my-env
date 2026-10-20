#!/usr/bin/env bash
set -u
L1="/media/yashar/Backups"
LOG="/home/yashar/logs/storagebox-watcher.log"
RUNNER="/home/yashar/storagebox-sync/bisync-run.sh"
DEBOUNCE=30
mkdir -p "$(dirname "$LOG")"
notified_missing=0
until /home/yashar/storagebox-sync/mount-check.sh; do
    if [ "$notified_missing" -eq 0 ]; then
        echo "$(date -Is) watcher: waiting for drive to return..." >> "$LOG"
        command -v notify-send >/dev/null && notify-send -u normal "storagebox sync" "drive absent - watcher waiting for re-attach" 2>/dev/null
        notified_missing=1
    fi
    sleep 45
done
[ "$notified_missing" -eq 1 ] && echo "$(date -Is) watcher: drive is back" >> "$LOG"
echo "$(date -Is) watcher started on $L1" >> "$LOG"

inotifywait -m -r -q \
    -e modify -e create -e delete -e move -e close_write \
    --format '%w%f %e' "$L1" 2>>"$LOG" | \
while read -r path event; do
    case "$path" in
        *.rclone*|*.partial*|*.swp|*~) continue ;;
    esac
    echo "$(date -Is) change: $event $path" >> "$LOG"
    pending=1
    while [ "$pending" -eq 1 ]; do
        pending=0
        sleep "$DEBOUNCE"
        if read -r -t 1 p2 e2 2>/dev/null; then
            echo "$(date -Is) change: $e2 $p2" >> "$LOG"
            pending=1
        fi
    done
    echo "$(date -Is) quiet ${DEBOUNCE}s - triggering bisync" >> "$LOG"
    "$RUNNER" >> "$LOG" 2>&1
    echo "$(date -Is) bisync run finished" >> "$LOG"
    while read -r -t 1 p3 e3 2>/dev/null; do
        :
    done
done
