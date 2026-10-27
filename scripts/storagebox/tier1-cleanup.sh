#!/usr/bin/env bash
# tier1-cleanup.sh — waits for local junk deletion to finish, mirrors the
# deletions on the Storage Box, then re-initializes bisync (fresh resync)
# and refreshes the merkle picture. Telegram-pings the result.
set -u
LOG=/home/yashar/logs/tier1-cleanup.log
RCF=/home/yashar/.config/rclone/rclone.conf
RCLONE=/usr/local/bin/rclone
B=/media/yashar/Backups

set -a; source /home/yashar/.config/ailaw-pr-review/env; set +a
SEND=/home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh
log() { echo "$(date -Is) $*" >> "$LOG"; }

# 1. wait for local venv cleanup to finish
while [ ! -f /tmp/opencode/venvclean.done ]; do sleep 20; done
log "local venv cleanup finished"

# 2. mirror deletions on the Box (same trees + fragments)
for d in "found.000"; do
    log "purging remote $d"
    "$RCLONE" purge "hetzner-sftp:/$d" --config "$RCF" >> "$LOG" 2>&1
done
while IFS= read -r d; do
    [ -d "$B/$d" ] && continue           # reappeared? skip (safety)
    log "purging remote $d"
    "$RCLONE" purge "hetzner-sftp:/$d" --config "$RCF" >> "$LOG" 2>&1
done < /tmp/opencode/junk-roots.txt
log "remote purges done"

# 3. fresh bisync init with temporarily raised delete guards
log "starting bisync resync (raised guards)"
/home/yashar/storagebox-sync/bisync-run.sh --resync \
    --max-delete 100000 --max-delete-size 500G
rc=$?
log "resync exit=$rc"

# 4. merkle refresh (re-baseline post-cleanup)
/home/yashar/storagebox-sync/merkle-snap.sh >> "$LOG" 2>&1

if [ "$rc" -eq 0 ]; then
    free=$(df -h "$B" | tail -1 | awk '{print $4}')
    say "🧹 Tier-1 cleanup DONE — venvs/caches/partials cleared on HDD+Box, bisync re-initialized (guards back to normal). Free space: $free"
else
    say "❌ Tier-1 cleanup: resync exited $rc — check $LOG"
fi
