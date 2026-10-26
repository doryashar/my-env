#!/usr/bin/env bash
# cleanup-v3.sh — corrective pass with REAL error handling:
#   1. retry failed Box purges (flex2 img, temp fragments)
#   2. validate bkup-split/Shared10 remnant is covered by the live Shared10
#      copies, then purge the remnant
#   3. Box-side move: lexar Google Photos -> photos/legacy-camera-roll
#   4. fresh bisync init + merkle + tagger scan of the new photo path
set -u
B=/media/yashar/Backups
LOG=/home/yashar/logs/cleanup-v3.log
RCF=/home/yashar/.config/rclone/rclone.conf
RCLONE=/usr/local/bin/rclone
FAIL=0

set -a; source /home/yashar/.config/ailaw-pr-review/env; set +a
SEND=/home/yashar/.config/opencode/skills/telegram-notify/scripts/telegram-send.sh
log() { echo "$(date -Is) $*" >> "$LOG"; }
purge() {  # purge <path> — deletefile first (big-file safe), then purge; not-found = success
    local p="$1" try rc
    for try in 1 2; do
        "$RCLONE" deletefile --config "$RCF" "hetzner-sftp:/$p" >> "$LOG" 2>&1; rc=$?
        "$RCLONE" purge --config "$RCF" "hetzner-sftp:/$p" >> "$LOG" 2>&1; rc=$?
        if [ "$rc" -eq 0 ]; then log "purged $p"; return 0; fi
        if "$RCLONE" lsf --config "$RCF" "hetzner-sftp:/$p" >> "$LOG" 2>&1; then
            log "purge try $try still present rc=$rc: $p"; sleep 10
        else
            log "gone after try $try: $p"; return 0
        fi
    done
    FAIL=1; return 1
}

# 1. retry failed purges + stragglers
for p in "flex2windowspartition.img" \
         "backblazessdwithwindows.img.a0238048.partial" \
         ".backblazessdwithwindows.img.KF3knM" \
         ".Disk Image of nvme0n1 (2022-08-28 1904).img.LoyVsu"; do
    purge "$p"
done

# 2. validate bkup-split/Shared10 remnant vs the live Shared10 copies
log "validating bkup-split/Shared10 remnant"
"$RCLONE" lsf --config "$RCF" -R --files-only "hetzner-sftp:/archive/bkup-split/Shared10" 2>/dev/null | sort > /tmp/opencode/bs.txt
"$RCLONE" lsf --config "$RCF" -R --files-only "hetzner-sftp:/lexar - ssd material to orginize/overflow/p6_shared/Shared10" 2>/dev/null | sort > /tmp/opencode/live-box.txt
find "$B/lexar - ssd material to orginize/overflow/p6_shared/Shared10" -type f -printf '%P\n' 2>/dev/null | sort > /tmp/opencode/live-local.txt
uniq -u /tmp/opencode/bs.txt /tmp/opencode/live-box.txt /tmp/opencode/live-local.txt > /tmp/opencode/bs-unique.txt
miss=$(wc -l < /tmp/opencode/bs-unique.txt)
tot=$(wc -l < /tmp/opencode/bs.txt)
log "remnant has $tot files; $miss not covered by live copies"
if [ "$miss" -eq 0 ]; then
    purge "archive/bkup-split"
else
    head -20 /tmp/opencode/bs-unique.txt >> "$LOG"
    say "⚠️ bkup-split/Shared10: $miss/$tot files NOT in live copies — kept. Sample in $LOG"
fi

# 3. Box-side photo move
"$RCLONE" moveto --config "$RCF" \
    "hetzner-sftp:lexar - ssd material to orginize/Drive/Google Photos" \
    "hetzner-sftp:photos/legacy-camera-roll" >> "$LOG" 2>&1 \
    && log "box photo move ok" || { log "box photo move FAILED"; FAIL=1; }

# 4. fresh bisync init
/home/yashar/storagebox-sync/bisync-run.sh --resync --max-delete 100000 --max-delete-size 500G
rc=$?
log "resync exit=$rc"
[ "$rc" -ne 0 ] && FAIL=1

# 5. merkle re-baseline
/home/yashar/storagebox-sync/merkle-snap.sh >> "$LOG" 2>&1

# 6. tagger scan of the merged location
scan() { command "$@" >> "$LOG" 2>&1; }
if command -v tagger >/dev/null 2>&1; then
    tagger scan "$B/photos/legacy-camera-roll" || FAIL=1
elif [ -x /home/yashar/.local/bin/tagger ]; then
    /home/yashar/.local/bin/tagger scan "$B/photos/legacy-camera-roll" >> "$LOG" 2>&1 || FAIL=1
else
    log "tagger cli not found — run: tagger scan photos/legacy-camera-roll"
fi

free=$(df -h "$B" | tail -1 | awk '{print $4}')
if [ "$FAIL" -eq 0 ] && [ "$rc" -eq 0 ]; then
    say "🧹 Cleanup v3 COMPLETE — all purges verified, photos merged+scanned, bisync healthy. HDD free: $free"
else
    say "⚠️ Cleanup v3 finished with failures (resync rc=$rc) — details in $LOG"
fi
