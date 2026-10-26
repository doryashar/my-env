#!/usr/bin/env bash
# cleanup-v2.sh — finishes the great HDD slim-down:
#   local deletes (images/seaweedfs/bkup-split) + Google Photos move,
#   Box-side purge/move mirrors, fresh bisync init, merkle, tagger scan.
set -u
B=/media/yashar/Backups
LOG=/home/yashar/logs/cleanup-v2.log
RCF=/home/yashar/.config/rclone/rclone.conf
RCLONE=/usr/local/bin/rclone

set -a; source /home/yashar/.config/ailaw-pr-review/env; set +a
SEND=/home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh
log() { echo "$(date -Is) $*" >> "$LOG"; }

# 0. wait out any still-running local venv purge
while pgrep -f 'junk-roots.txt; echo DONE' >/dev/null 2>&1; do sleep 20; done
log "start"

# 1. local deletions
rm -f "$B/backblazessdwithwindows.img" "$B/flex2windowspartition.img" && log "images deleted"
rm -rf "$B/seaweedfs" && log "seaweedfs deleted"
rm -rf "$B/archive/bkup-split" && log "bkup-split deleted"
df -h "$B" | tail -1 | awk '{print "free after local deletes: "$4}' >> "$LOG"

# 2. local photo move (same fs = instant)
mkdir -p "$B/photos/legacy-camera-roll"
mv "$B/lexar - ssd material to orginize/Drive/Google Photos" "$B/photos/legacy-camera-roll/" && log "local Google Photos moved to photos/legacy-camera-roll"

# 3. Box-side mirrors
log "box: purging tier1 venv trees"
while IFS= read -r d; do
    [ -d "$B/$d" ] && continue
    "$RCLONE" purge "hetzner-sftp:/$d" --config "$RCF" >> "$LOG" 2>&1
done < /tmp/opencode/junk-roots.txt
log "box: purging big items"
for d in "backblazessdwithwindows.img" "flex2windowspartition.img" "seaweedfs" "archive/bkup-split" "found.000"; do
    "$RCLONE" purge "hetzner-sftp:/$d" --config "$RCF" >> "$LOG" 2>&1
    log "box: purged $d"
done
log "box: moving Google Photos"
"$RCLONE" moveto "hetzner-sftp:lexar - ssd material to orginize/Drive/Google Photos" \
                 "hetzner-sftp:photos/legacy-camera-roll" --config "$RCF" >> "$LOG" 2>&1 \
    && log "box move ok" || log "box move WARN (may already be moved)"

# 4. fresh bisync init
log "bisync resync (raised guards)"
/home/yashar/storagebox-sync/bisync-run.sh --resync --max-delete 100000 --max-delete-size 500G
rc=$?
log "resync exit=$rc"

# 5. merkle re-baseline
/home/yashar/storagebox-sync/merkle-snap.sh >> "$LOG" 2>&1

# 6. tagger scan of the new photo location (metadata + faces, incremental)
sudo -u yashar env HOME=/home/yashar /home/yashar/.local/bin/tagger scan "$B/photos/legacy-camera-roll" >> "$LOG" 2>&1 \
    || /home/yashar/.local/bin/tagger scan "$B/photos/legacy-camera-roll" >> "$LOG" 2>&1 \
    || log "tagger scan skipped (cli not found at expected path)"

free=$(df -h "$B" | tail -1 | awk '{print $4}')
if [ "$rc" -eq 0 ]; then
    "$SEND" "🧹 Cleanup v2 COMPLETE — images/seaweedfs/bkup-split gone (both sides), photos merged into photos/legacy-camera-roll, bisync re-initialized, tagger scanning. HDD free: $free"
else
    "$SEND" --loud "⚠️ Cleanup v2 finished but bisync init exited $rc — check $LOG"
fi
